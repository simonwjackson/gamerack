#!/usr/bin/env bash

check_environment_variables() {
  missing_vars=()

  [[ -z "${STEAM_API_KEY}" ]] && missing_vars+=("STEAM_API_KEY")
  [[ -z "${STEAM_ID}" ]] && missing_vars+=("STEAM_ID")

  if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Missing environment variables: ${missing_vars[*]}"
    exit 1
  fi
}

steam_api_url() {
  case "$1" in
  "reviews")
    echo "https://store.steampowered.com/appreviews/{$2}?json=1"
    ;;
  "owned_games")
    echo "https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=${2}&steamid=${3}&format=json"
    ;;
  "details")
    echo "https://store.steampowered.com/api/appdetails?appids={$2}"
    ;;
  *)
    echo "Invalid steam_api_url option."
    exit
    ;;
  esac
}

get_new_steam_app_ids() {
  {
    curl \
      --show-error \
      --silent \
      --location \
      "$(steam_api_url owned_games "${STEAM_API_KEY}" "${STEAM_ID}")" |
      jq \
        --raw-output \
        '.response.games[] | .appid'
    yq \
      --output-format json \
      '.games[].store.steam.id' \
      "${GAME_DATABASE_FILE}"
  } |
    sort --numeric-sort |
    uniq --unique
}

update_game_database() {
  new_steam_games=$(
    get_new_steam_app_ids |
      jq \
        --slurp \
        --compact-output \
        '[.[] | { store: { steam: { id: tonumber }}}]'
  ) yq eval \
    --prettyPrint \
    --inplace \
    --output-format yaml \
    '.games += (strenv(new_steam_games) | fromjson)' \
    "${GAME_DATABASE_FILE}"
}

get_app_ids_without_meta() {
  yq \
    --output-format json \
    --exit-status \
    '.games[]
       | select(
         .store.steam.id != null
         and (has("name") | not)
         and (
           .store.steam.removed != true
           or .store.steam.removed == null
         )
       )
       | .store.steam.id' \
    "${GAME_DATABASE_FILE}" |
    jq \
      --compact-output
}

update_game_details() {
  local steam_app_id=$1

  details=$(
    curl \
      --show-error \
      --silent \
      --location \
      "$(steam_api_url details "${steam_app_id}")"
  )

  original_entry=$(
    APP_ID="$steam_app_id" yq \
      --output-format json \
      '.games[] | select(.store.steam.id == (strenv(APP_ID)))' \
      "${GAME_DATABASE_FILE}" |
      jq \
        --compact-output
  )

  if ! jq --arg APPID "${steam_app_id}" --exit-status '.[$APPID].data' <<<"${details}" &>/dev/null; then
    echo "Removed from store: ${steam_app_id}"
    export new_data

    new_data=$(
      {
        echo -e '{
          "store": {
            "steam": {
              "removed": true
            }
          }
        }'
        echo -e "${original_entry}"
      } |
        jq \
          --compact-output \
          --slurp \
          -r \
          '.[0] * .[1]'
    )
  else
    echo "Steam: ${steam_app_id}"

    new_data=$(
      {
        jq \
          --compact-output \
          --raw-output \
          --arg APPID "${steam_app_id}" \
          '.[$APPID].data | {
            name: .name?,
            platform: "steam",
            released: .release_date?,
            score: {
              mc: .metacritic.score?
            },
            media: {
              images: {
                background: .background_raw?,
                header: .header_image?,
                capsule: .capsule_image?,
                screenshots: (.screenshots // []) | map({ url: .path_full? })
              },
              videos: (.movies // []) | map({
                title: .name?,
                thumb: .thumbnail?,
                url: .mp4?.max?
              })
            },
            genres: [(.genres // [])[].description?],
            tags: [(.categories // [])[].description?],
            description: {
              detailed: (.detailed_description? | gsub("[^\\x20-\\x7E]"; "")),
              short: (.short_description? | gsub("[^\\x20-\\x7E]"; ""))
            }
          }' \
          <<<"${details}"
        echo -e "$original_entry"
      } |
        jq --slurp -r '.[0] * .[1]'
    )
  fi

  # TODO: This selector seems to be broken with the upgrade to yq 4.0
  NEW_DATA="${new_data}" STEAM_APP_ID="${steam_app_id}" yq \
    --prettyPrint \
    --inplace \
    --output-format yaml \
    '(.games[] | select(.store.steam.id == strenv(STEAM_APP_ID)) | .) |= (strenv(NEW_DATA) | fromjson)' \
    "${GAME_DATABASE_FILE}"

  sleep 2
}

get_app_ids_without_review() {
  yq \
    --output-format json \
    '.games[]
     | select(
         .store.steam.id != null
         and .score.steam == null
       )
     | .store.steam.id
    ' \
    "${GAME_DATABASE_FILE}" |
    jq \
      --compact-output
}

update_game_reviews() {
  local app_id=$1

  echo "Fetching review: ${app_id}"

  read -r total_positive total_reviews < <(
    curl \
      --show-error \
      --silent \
      --location \
      "$(steam_api_url reviews "${app_id}")" |
      jq \
        --raw-output \
        '.query_summary | "\(.total_positive) \(.total_reviews)"'
  )

  if ! [[ $total_positive =~ ^[0-9]+$ ]] || ! [[ $total_reviews =~ ^[0-9]+$ ]]; then
    echo "Invalid total_positive or total_reviews value. Skipping.."
    return
  fi

  sleep 2

  z=1.96
  n=$total_reviews
  p=$(echo "scale=10; $total_positive/$n" | bc)

  wilson_score_percentage=$(
    echo "scale=10; ($p + ($z^2)/(2*$n) - $z*sqrt(($p*(1-$p))/$n + ($z^2)/(4*$n^2)))/(1+($z^2)/$n)*100" |
      bc
  )

  if ! [[ $wilson_score_percentage =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid wilson_score_percentage value. Skipping.."
    return
  fi

  APPID="${app_id}" SCORE="$(printf "%.0f" "${wilson_score_percentage}")" yq eval \
    --inplace \
    --output-format yaml \
    '(.games[] | select(.store.steam.id == strenv(APPID))).score.steam |= env(SCORE)' \
    "${GAME_DATABASE_FILE}"
}

main() {
  # local -n args=$1

  check_environment_variables

  update_game_database

  without_meta=$(get_app_ids_without_meta)
  IFS=$'\n' read -rd '' -a appid_array <<<"${without_meta}"
  for steam_app_id in "${appid_array[@]}"; do
    update_game_details "${steam_app_id}"
  done

  without_review=$(get_app_ids_without_review)
  IFS=$'\n' read -rd '' -a appid_array <<<"${without_review}"
  for app_id in "${appid_array[@]}"; do
    update_game_reviews "${app_id}"
  done
}

main "ARGS"
