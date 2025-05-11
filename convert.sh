#!/bin/bash

NODE_FILE="/etc/s-box-ag/jh.txt"
NODE_DIR=$(dirname "$NODE_FILE")
SING_BOX_CONFIG="$NODE_DIR/sing_box_client.json"
CLASH_CONFIG="$NODE_DIR/clash_meta_client.yaml"

> "$SING_BOX_CONFIG"
> "$CLASH_CONFIG"

NODE_NAME_1=$(sed -n '11p' "$NODE_FILE")
NODE_NAME_2=$(sed -n '12p' "$NODE_FILE")

echo "{" > "$SING_BOX_CONFIG"
echo '  "outbounds": [' >> "$SING_BOX_CONFIG"
echo "proxies:" > "$CLASH_CONFIG"

node_counter=0
while IFS= read -r line; do
  if [ "$node_counter" -eq 10 ] || [ "$node_counter" -eq 11 ]; then
    node_counter=$((node_counter + 1))
    continue
  fi

  if [[ "$line" =~ vmess:// ]]; then
    uuid=$(echo "$line" | base64 -d | jq -r '.id')
    server=$(echo "$line" | base64 -d | jq -r '.add')
    port=$(echo "$line" | base64 -d | jq -r '.port')
    tls=$(echo "$line" | base64 -d | jq -r '.tls')

    if [ "$node_counter" -gt 0 ]; then echo ',' >> "$SING_BOX_CONFIG"; fi
    echo "    {" >> "$SING_BOX_CONFIG"
    echo "      \"type\": \"vmess\"," >> "$SING_BOX_CONFIG"
    echo "      \"server\": \"$server\"," >> "$SING_BOX_CONFIG"
    echo "      \"server_port\": $port," >> "$SING_BOX_CONFIG"
    echo "      \"uuid\": \"$uuid\"," >> "$SING_BOX_CONFIG"
    echo "      \"tls\": {\"enabled\": $tls}" >> "$SING_BOX_CONFIG"
    echo "    }" >> "$SING_BOX_CONFIG"

    echo "  - name: \"$NODE_NAME_1\"" >> "$CLASH_CONFIG"
    echo "    type: vmess" >> "$CLASH_CONFIG"
    echo "    server: $server" >> "$CLASH_CONFIG"
    echo "    port: $port" >> "$CLASH_CONFIG"
    echo "    uuid: $uuid" >> "$CLASH_CONFIG"
    echo "    tls: $tls" >> "$CLASH_CONFIG"
    echo "    alterId: 0" >> "$CLASH_CONFIG"
    echo "    cipher: auto" >> "$CLASH_CONFIG"

  elif [[ "$line" =~ ss:// ]]; then
    server=$(echo "$line" | cut -d '@' -f2 | cut -d ':' -f1)
    port=$(echo "$line" | cut -d '@' -f2 | cut -d ':' -f2)
    password=$(echo "$line" | cut -d ':' -f2 | cut -d '@' -f1)
    method=$(echo "$line" | cut -d ':' -f1 | cut -d '/' -f3)

    if [ "$node_counter" -gt 0 ]; then echo ',' >> "$SING_BOX_CONFIG"; fi
    echo "    {" >> "$SING_BOX_CONFIG"
    echo "      \"type\": \"ss\"," >> "$SING_BOX_CONFIG"
    echo "      \"server\": \"$server\"," >> "$SING_BOX_CONFIG"
    echo "      \"server_port\": $port," >> "$SING_BOX_CONFIG"
    echo "      \"password\": \"$password\"," >> "$SING_BOX_CONFIG"
    echo "      \"method\": \"$method\"" >> "$SING_BOX_CONFIG"
    echo "    }" >> "$SING_BOX_CONFIG"

    echo "  - name: \"$NODE_NAME_2\"" >> "$CLASH_CONFIG"
    echo "    type: ss" >> "$CLASH_CONFIG"
    echo "    server: $server" >> "$CLASH_CONFIG"
    echo "    port: $port" >> "$CLASH_CONFIG"
    echo "    password: $password" >> "$CLASH_CONFIG"
    echo "    method: $method" >> "$CLASH_CONFIG"

  elif [[ "$line" =~ trojan:// ]]; then
    server=$(echo "$line" | cut -d '@' -f2 | cut -d ':' -f1)
    port=$(echo "$line" | cut -d '@' -f2 | cut -d ':' -f2)
    password=$(echo "$line" | cut -d '/' -f3)

    if [ "$node_counter" -gt 0 ]; then echo ',' >> "$SING_BOX_CONFIG"; fi
    echo "    {" >> "$SING_BOX_CONFIG"
    echo "      \"type\": \"trojan\"," >> "$SING_BOX_CONFIG"
    echo "      \"server\": \"$server\"," >> "$SING_BOX_CONFIG"
    echo "      \"server_port\": $port," >> "$SING_BOX_CONFIG"
    echo "      \"password\": \"$password\"" >> "$SING_BOX_CONFIG"
    echo "    }" >> "$SING_BOX_CONFIG"

    echo "  - name: \"$NODE_NAME_2\"" >> "$CLASH_CONFIG"
    echo "    type: trojan" >> "$CLASH_CONFIG"
    echo "    server: $server" >> "$CLASH_CONFIG"
    echo "    port: $port" >> "$CLASH_CONFIG"
    echo "    password: $password" >> "$CLASH_CONFIG"
  fi

  node_counter=$((node_counter + 1))
done < "$NODE_FILE"

echo "  ]" >> "$SING_BOX_CONFIG"
echo "}" >> "$SING_BOX_CONFIG"

echo "proxy-groups:" >> "$CLASH_CONFIG"
echo "  - name: 自动选择" >> "$CLASH_CONFIG"
echo "    type: select" >> "$CLASH_CONFIG"
echo "    proxies:" >> "$CLASH_CONFIG"

: "${TOKEN:=}"
: "${GIT_USER:=}"
: "${GIT_EMAIL:=}"
: "${PROJECT:=}"

[ -z "$TOKEN" ] && read -p "GitLab Token: " TOKEN
[ -z "$GIT_USER" ] && read -p "GitLab 用户名: " GIT_USER
[ -z "$GIT_EMAIL" ] && read -p "GitLab 邮箱: " GIT_EMAIL
[ -z "$PROJECT" ] && read -p "GitLab 项目名: " PROJECT

TMP_DIR="/tmp/idx_upload"
FILES=(
  "$NODE_DIR/sing_box_client.json"
  "$NODE_DIR/clash_meta_client.yaml"
  "$NODE_DIR/jh.txt"
)

git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"

for FILE in "${FILES[@]}"; do
  if [ ! -f "$FILE" ]; then
    echo "缺少文件：$FILE"
    exit 1
  fi
done

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR" || exit 1

git clone https://oauth2:$TOKEN@gitlab.com/$GIT_USER/$PROJECT.git
cd "$PROJECT" || exit 1

for FILE in "${FILES[@]}"; do
  BASENAME=$(basename "$FILE")
  cp "$FILE" "./$BASENAME"
  sed -i 's/ \{1,\}/ /g' "$BASENAME"
done

git add *.json *.yaml jh.txt
git commit -m "更新订阅文件 $(date '+%Y-%m-%d %H:%M:%S')" || echo "无变更"
git push origin main --force 2>/dev/null || git push origin master --force

echo "上传完成：$PROJECT 项目"
