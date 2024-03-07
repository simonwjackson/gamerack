#!/usr/bin/env bash

CURL_OPTS=(
  --show-error
  --silent
  -H 'Accept-Encoding: gzip, deflate, br'
  -H 'Accept-Language: en-US,en;q=0.5'
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
  -H 'Connection: keep-alive'
  -H 'Content-Type: application/x-www-form-urlencoded'
  -H 'Origin: https://www.mobygames.com'
  -H 'Save-Data: on'
  -H 'Sec-Fetch-Dest: document'
  -H 'Sec-Fetch-Mode: navigate'
  -H 'Sec-Fetch-Site: same-origin'
  -H 'Sec-Fetch-User: ?1'
  -H 'TE: trailers'
  -H 'Upgrade-Insecure-Requests: 1'
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0'
)

login_to_mobygames() {
  csrf_token=$(
    curl \
      --cookie-jar "${MOBY_COOKIE_FILE}" \
      'https://www.mobygames.com/user/login/' |
      pup 'body input[name="_csrf_token"] attr{value}'
  )

  curl \
    --cookie "${MOBY_COOKIE_FILE}" \
    --cookie-jar "${MOBY_COOKIE_FILE}" \
    -X POST \
    "${CURL_OPTS[@]}" \
    --data-raw "_csrf_token=${csrf_token}&login=${MOBY_USERNAME}&password=${MOBY_PASSWORD}" \
    'https://www.mobygames.com/user/login/' &>/dev/null
}

get_moby_ids() {
  {
    curl \
      --cookie "${MOBY_COOKIE_FILE}" \
      "${CURL_OPTS[@]}" \
      "https://www.mobygames.com/user/list/export/Collection_${MOBY_COLLECTION_ID}_public.csv" |
      mlr \
        --c2j \
        cat |
      jq \
        --raw-output \
        '.[].game_id'
    yq \
      '.games[].store.moby.id' \
      "${GAME_DATABASE_FILE}" |
      tr ' ' '\n'
  } |
    sort --numeric-sort |
    uniq --unique
}

get_new_games() {
  new_games=$(
    get_moby_ids |
      jq \
        --slurp \
        --compact-output \
        '[.[] | { store: { moby: { id: tonumber }}}]'
  )

  yq \
    --in-place \
    --yaml-output \
    --argjson new_numbers "${new_games}" \
    '.games += [$''new_numbers[]]' \
    "${GAME_DATABASE_FILE}"
}

fetch_game_details() {
  local app_id=$1
  echo "ID: $app_id"
  details=$(
    curl \
      --show-error \
      --silent \
      --location \
      "https://api.mobygames.com/v1/games/{$app_id}?api_key=${MOBY_API_KEY}"
  )

  new_data=$(
    {
      echo "${details}" | jq --arg APPID "${app_id}" '{
          name: .title?,
          description: {
            detailed: ((.description // "" ) | gsub("[^\\x20-\\x7E]"; "")),
          },
          genres: [(.genres // [])[].genre_name?],
          score: {
            moby: .moby_score?
          },
          platform: .platforms?[0].platform_name?,
          media: {
            images: {
              cover: .sample_cover.image?,
              screenshots: (.sample_screenshots // []) | map({ title: .caption?, url: .image? })
            }
          }
        }'
      yq \
        --arg APPID "${app_id}" \
        '.games[] | select(.store.moby.id == ($''APPID | tonumber))' "${GAME_DATABASE_FILE}"
    } |
      jq \
        --slurp \
        --raw-output \
        '(.[0] // {}) * (.[1] // {})'
  )

  yq \
    --yaml-output \
    --in-place \
    --argjson NEW_DATA "${new_data}" \
    '( .games[] | select(.store.moby.id == $''NEW_DATA.store.moby.id) | . ) |= $''NEW_DATA' "${GAME_DATABASE_FILE}"
}

main() {
  missing_vars=()

  [[ -z "${MOBY_API_KEY}" ]] && missing_vars+=("MOBY_API_KEY")
  [[ -z "${MOBY_COOKIE_FILE}" ]] && missing_vars+=("MOBY_COOKIE_FILE")
  [[ -z "${MOBY_COLLECTION_ID}" ]] && missing_vars+=("MOBY_COLLECTION_ID")
  [[ -z "${MOBY_USERNAME}" ]] && missing_vars+=("MOBY_USERNAME")
  [[ -z "${MOBY_PASSWORD}" ]] && missing_vars+=("MOBY_PASSWORD")

  if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Missing environment variables: ${missing_vars[*]}"
    exit 1
  fi

  login_to_mobygames
  get_new_games

  without_name=$(
    yq --exit-status \
      '.games[] | select(.store.moby.id != null and (has("name") | not)) | .store.moby.id' \
      "${GAME_DATABASE_FILE}"
  )

  IFS=$'\n' read -rd '' -a appid_array <<<"${without_name}"
  for app_id in "${appid_array[@]}"; do
    fetch_game_details "$app_id"

    # API rate limiting
    sleep 10
  done
}

main "ARGS"

# All "endless" games
# .games | map(select(.user.status == "endless"))

# Top 3 games with a metacritic score
# games | sort_by(.score.mc) | reverse | .[0:3]'

# Highest (average) rated game. adjusted for games without review scores
# .games | map(select(.score | objects | any(.[]; . != null))) | sort_by(.score | to_entries | map(.value) | add / length) | reverse | .[0]

# Games with avalible files
# .games | map(select(.user?.resources? | .[]? | .host == "fiji" or .host == "zao"))

# Test data
#
# {
#   "games": [
#     {
#       "name": "mario",
#       "score": {
#         "steam": 5,
#         "mc": 4.8,
#         "moby": 1
#       }
#     },
#     {
#       "name": "zelda",
#       "score": {
#         "steam": 3,
#         "moby": 4
#       }
#     },
#     {
#       "name": "kirby",
#       "score": {}
#     },
#     {
#       "name": "metroid"
#     },
#     {
#       "name": "sonic",
#       "score": {
#         "moby": null
#       }
#     }
#   ]
# }
