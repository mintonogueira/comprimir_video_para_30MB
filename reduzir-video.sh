#!/usr/bin/env bash

set -Eeuo pipefail

DEFAULT_TARGET_MB="30"
AUDIO_KBPS="96"
SAFETY_PERCENT="97"
MIN_VIDEO_KBPS="50"

usage() {
    cat <<'EOF'
Uso:
  reduzir-video.sh <video> [tamanho_em_MB]

Exemplos:
  reduzir-video.sh 'video.mp4'
  reduzir-video.sh 'video.mp4' 30
  reduzir-video.sh 'video.mp4' 20

O tamanho padrão é 30 MB (30.000.000 bytes).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

INPUT="${1:-}"
TARGET_MB="${2:-$DEFAULT_TARGET_MB}"

if [[ -z "$INPUT" ]]; then
    usage
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    printf 'Erro: arquivo não encontrado: %s\n' "$INPUT" >&2
    exit 1
fi

if [[ ! "$TARGET_MB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Erro: tamanho inválido: %s MB\n' "$TARGET_MB" >&2
    exit 1
fi

for cmd in ffmpeg ffprobe awk mktemp wc tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf "Erro: dependência ausente: '%s'.\n" "$cmd" >&2
        exit 1
    fi
done

DURATION="$(
    ffprobe \
        -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$INPUT"
)"

if [[ -z "$DURATION" ]] || ! awk -v d="$DURATION" 'BEGIN { exit !(d > 0) }'; then
    echo 'Erro: não foi possível determinar uma duração válida para o vídeo.' >&2
    exit 1
fi

HAS_AUDIO="$(
    ffprobe \
        -v error \
        -select_streams a:0 \
        -show_entries stream=index \
        -of csv=p=0 \
        "$INPUT" 2>/dev/null || true
)"

if [[ -n "$HAS_AUDIO" ]]; then
    EFFECTIVE_AUDIO_KBPS="$AUDIO_KBPS"
else
    EFFECTIVE_AUDIO_KBPS="0"
fi

TARGET_BYTES="$(
    awk -v mb="$TARGET_MB" 'BEGIN { printf "%.0f", mb * 1000 * 1000 }'
)"

SAFE_BYTES="$(
    awk \
        -v bytes="$TARGET_BYTES" \
        -v margin="$SAFETY_PERCENT" \
        'BEGIN { printf "%.0f", bytes * margin / 100 }'
)"

VIDEO_KBPS="$(
    awk \
        -v bytes="$SAFE_BYTES" \
        -v duration="$DURATION" \
        -v audio="$EFFECTIVE_AUDIO_KBPS" \
        'BEGIN {
            total_kbps = (bytes * 8) / duration / 1000;
            video_kbps = total_kbps - audio;
            printf "%.0f", video_kbps;
        }'
)"

if ! awk -v v="$VIDEO_KBPS" -v min="$MIN_VIDEO_KBPS" 'BEGIN { exit !(v >= min) }'; then
    cat >&2 <<EOF
Erro: o tamanho solicitado é pequeno demais para esta duração.
Bitrate de vídeo calculado: ${VIDEO_KBPS} kbps
Mínimo operacional adotado: ${MIN_VIDEO_KBPS} kbps

Tente um tamanho final maior ou reduza manualmente a duração/resolução do vídeo.
EOF
    exit 1
fi

INPUT_DIR="$(dirname -- "$INPUT")"
INPUT_NAME="$(basename -- "$INPUT")"
STEM="${INPUT_NAME%.*}"
OUTPUT="${INPUT_DIR}/${STEM} - ${TARGET_MB}MB.mp4"

TMP_DIR="$(mktemp -d)"
PASSLOG="${TMP_DIR}/ffmpeg2pass"

cleanup() {
    rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT INT TERM

printf '\nArquivo de entrada : %s\n' "$INPUT"
printf 'Duração            : %.2f s\n' "$DURATION"
printf 'Tamanho máximo     : %s MB\n' "$TARGET_MB"
printf 'Margem de segurança: %s%% do limite\n' "$SAFETY_PERCENT"
printf 'Bitrate de vídeo   : %s kbps\n' "$VIDEO_KBPS"
printf 'Bitrate de áudio   : %s kbps\n' "$EFFECTIVE_AUDIO_KBPS"
printf 'Arquivo de saída   : %s\n\n' "$OUTPUT"

echo 'Passagem 1/2: analisando o vídeo...'
ffmpeg \
    -y \
    -i "$INPUT" \
    -map 0:v:0 \
    -c:v libx264 \
    -b:v "${VIDEO_KBPS}k" \
    -preset slow \
    -pass 1 \
    -passlogfile "$PASSLOG" \
    -an \
    -f null \
    /dev/null

echo
echo 'Passagem 2/2: gerando o arquivo final...'

FFMPEG_AUDIO_ARGS=()
if [[ -n "$HAS_AUDIO" ]]; then
    FFMPEG_AUDIO_ARGS=(
        -map 0:a:0?
        -c:a aac
        -b:a "${AUDIO_KBPS}k"
    )
fi

ffmpeg \
    -y \
    -i "$INPUT" \
    -map 0:v:0 \
    "${FFMPEG_AUDIO_ARGS[@]}" \
    -c:v libx264 \
    -b:v "${VIDEO_KBPS}k" \
    -preset slow \
    -pass 2 \
    -passlogfile "$PASSLOG" \
    -pix_fmt yuv420p \
    -movflags +faststart \
    "$OUTPUT"

FINAL_BYTES="$(wc -c < "$OUTPUT" | tr -d '[:space:]')"
FINAL_MB="$(awk -v bytes="$FINAL_BYTES" 'BEGIN { printf "%.2f", bytes / 1000 / 1000 }')"

printf '\n========================================\n'
printf 'Conversão concluída\n'
printf '========================================\n'
printf 'Arquivo : %s\n' "$OUTPUT"
printf 'Tamanho : %s MB (%s bytes)\n' "$FINAL_MB" "$FINAL_BYTES"

if (( FINAL_BYTES > TARGET_BYTES )); then
    cat >&2 <<EOF

Aviso: o arquivo ficou acima do limite solicitado.
Isso pode ocorrer por variações de mux/container. Tente novamente com um alvo ligeiramente menor.
EOF
    exit 2
fi

printf 'Status  : dentro do limite de %s MB\n' "$TARGET_MB"
