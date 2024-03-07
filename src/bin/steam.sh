#!/usr/bin/env bash

main() {
  # local -n args=$1

  missing_vars=()

  [[ -z "${STEAM_API_KEY}" ]] && missing_vars+=("STEAM_API_KEY")
  [[ -z "${STEAM_ID}" ]] && missing_vars+=("STEAM_ID")

  # If there are any missing variables, show them and exit
  if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Missing environment variables: ${missing_vars[*]}"
    exit 1
  fi

  # printf "Finding all owned steam games.."

  steam_app_ids=$(
    {
      curl \
        --show-error \
        --silent \
        --location \
        "https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=${STEAM_API_KEY}&steamid=${STEAM_ID}&format=json" |
        jq \
          --raw-output \
          '.response.games[] | .appid'
      yq \
        '.games[].store.steam.id' \
        "${GAME_DATABASE_FILE}"
    } |
      sort --numeric-sort |
      uniq --unique
  )

  new_steam_games=$(
    jq \
      --slurp \
      --compact-output \
      '[.[] | { store: { steam: { id: tonumber }}}]' \
      <<<"${steam_app_ids}"
  )

  yq \
    --in-place \
    --yaml-output \
    --argjson new_steam_games "${new_steam_games}" \
    '.games += [$''new_steam_games[]]' \
    "${GAME_DATABASE_FILE}"

  printf "done\n"

  without_meta=$(
    yq \
      --compact-output \
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
      "${GAME_DATABASE_FILE}"
  )

  IFS=$'\n' read -rd '' -a appid_array <<<"${without_meta}"
  for steam_app_id in "${appid_array[@]}"; do
    # TODO: curl might fail for many reasons, account for this.

    details=$(
      curl \
        --show-error \
        --silent \
        --location \
        "https://store.steampowered.com/api/appdetails?appids={$steam_app_id}"
    )

    original_entry=$(
      yq \
        --compact-output \
        --arg APPID "${steam_app_id}" \
        '.games[] | select(.store.steam.id == ($''APPID | tonumber))' \
        "${GAME_DATABASE_FILE}"
    )

    if ! jq --arg APPID "${steam_app_id}" --exit-status '.[$APPID].data' <<<"${details}" &>/dev/null; then
      echo "Removed from store: ${steam_app_id}"

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

    yq \
      --in-place \
      --yaml-output \
      --argjson pipe "${new_data}" \
      '(.games[] | select(.store.steam.id == $''pipe.store.steam.id) | .) |= $''pipe' \
      "${GAME_DATABASE_FILE}"

    sleep 2
  done

  without_review=$(
    yq \
      --compact-output \
      '.games[]
     | select(
         .store.steam.id != null
         and .score.steam == null
       )
     | .store.steam.id
    ' \
      "${GAME_DATABASE_FILE}"
  )

  IFS=$'\n' read -rd '' -a appid_array <<<"${without_review}"
  for appid in "${appid_array[@]}"; do
    # TODO: curl might fail for many reasons, account for this.

    # read -r total_positive total_reviews <<<"$(
    #   curl \
    #     --show-error \
    #     --silent \
    #     --location \
    #     "https://store.steampowered.com/appreviews/{$appid}?json=1" |
    #     jq \
    #       --raw-output \
    #       '.query_summary | "\(.total_positive) \(.total_reviews)"'
    # )"

    read -r total_positive total_reviews < <(
      curl \
        --show-error \
        --silent \
        --location \
        "https://store.steampowered.com/appreviews/{$appid}?json=1" |
        jq \
          --raw-output \
          '.query_summary | "\(.total_positive) \(.total_reviews)"'
    )

    sleep 2

    z=1.96
    n=$total_reviews
    p=$(echo "scale=10; $total_positive/$n" | bc)

    # TODO: Somehwere here were dividing by zero. game removed from steam?

    wilson_score_percentage=$(
      echo "scale=10; ($p + ($z^2)/(2*$n) - $z*sqrt(($p*(1-$p))/$n + ($z^2)/(4*$n^2)))/(1+($z^2)/$n)*100" |
        bc
    )

    yq \
      --in-place \
      --yaml-output \
      --arg SCORE "$(printf "%.0f" "${wilson_score_percentage}")" \
      --arg APPID "${appid}" \
      '(.games[] | select(.store.steam.id == $''APPID)).score.steam |= ($''SCORE | tonumber)' \
      "${GAME_DATABASE_FILE}"
  done
}

main "ARGS"
