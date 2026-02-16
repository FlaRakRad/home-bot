#!/bin/bash

URL="$1"
DOWNLOAD_DIR="$(dirname "$0")/downloads"
mkdir -p "$DOWNLOAD_DIR"

LOG_FILE="$DOWNLOAD_DIR/debug.log"
> "$LOG_FILE"

VIDEO_FILE=""
AUDIO_FILE=""
TITLE="Unknown"
ARTIST="Unknown"
THUMB_FILE=""
DURATION=0

error_exit() {
    jq -n --arg err "$1" '{error: $err}'
    exit 1
}
download_tiktok() {
    local url="$1"
    echo "=== TikTok Downloader ==="
    
    echo "Resolving URL..."
    local FULL_URL=$(curl -sLI -o /dev/null -w '%{url_effective}' "$url" | head -n1)
    echo "Full URL: $FULL_URL"
    
    local VIDEO_ID=""
    
    VIDEO_ID=$(echo "$FULL_URL" | grep -oP '(?<=video/)\d+' | head -n1)
    
    if [ -z "$VIDEO_ID" ]; then
        VIDEO_ID=$(echo "$url" | grep -oP '(?<=video/)\d+' | head -n1)
    fi
    
    if [ -z "$VIDEO_ID" ]; then
        VIDEO_ID=$(echo "$url" | grep -oP '\d{19}' | head -n1)
    fi
    
    if [ -z "$VIDEO_ID" ]; then
        echo "ERROR: Cannot extract video ID"
        return 1
    fi
    
    echo "Video ID: $VIDEO_ID"
    
    local TIKTOK_URL="https://www.tiktok.com/@x/video/${VIDEO_ID}"
    
    echo "Trying TikWM API..."
    local RESPONSE=$(curl -s -X POST "https://www.tikwm.com/api/" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "url=${TIKTOK_URL}" 2>&1)
    
    local CODE=$(echo "$RESPONSE" | jq -r '.code // -1' 2>/dev/null)
    
    if [ "$CODE" = "0" ]; then
        echo "TikWM API success!"
        
        local VIDEO_URL=$(echo "$RESPONSE" | jq -r '.data.play // ""' 2>/dev/null)
        TITLE=$(echo "$RESPONSE" | jq -r '.data.title // "TikTok Video"' 2>/dev/null)
        ARTIST=$(echo "$RESPONSE" | jq -r '.data.author.unique_id // "TikTok"' 2>/dev/null)
        local THUMB_URL=$(echo "$RESPONSE" | jq -r '.data.cover // ""' 2>/dev/null)
        DURATION=$(echo "$RESPONSE" | jq -r '.data.duration // 0' 2>/dev/null)
        
        if [ ! -z "$VIDEO_URL" ] && [ "$VIDEO_URL" != "null" ]; then
            echo "Downloading video from: ${VIDEO_URL:0:60}..."
            VIDEO_FILE="$DOWNLOAD_DIR/video.mp4"
            
            if curl -L -o "$VIDEO_FILE" "$VIDEO_URL" 2>&1; then
                if [ -f "$VIDEO_FILE" ] && [ -s "$VIDEO_FILE" ]; then
                    echo "Video downloaded: $(stat -c%s "$VIDEO_FILE" 2>/dev/null) bytes"
                    
                    if [ ! -z "$THUMB_URL" ] && [ "$THUMB_URL" != "null" ]; then
                        echo "Downloading thumbnail..."
                        THUMB_FILE="$DOWNLOAD_DIR/thumb.jpg"
                        curl -s -L -o "$THUMB_FILE" "$THUMB_URL" 2>&1
                    fi
                    
                    return 0
                fi
            fi
        fi
    fi
    
    echo "TikWM failed, trying MusicalDown API..."
    
    local RESPONSE2=$(curl -s -X POST "https://musicaldown.com/download" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "url=${TIKTOK_URL}" 2>&1)
    
    local VIDEO_URL2=$(echo "$RESPONSE2" | grep -oP 'href="[^"]*download[^"]*"' | head -n1 | cut -d'"' -f2)
    
    if [ ! -z "$VIDEO_URL2" ]; then
        echo "MusicalDown API success!"
        echo "Downloading video..."
        VIDEO_FILE="$DOWNLOAD_DIR/video.mp4"
        
        if curl -L -o "$VIDEO_FILE" "$VIDEO_URL2" 2>&1; then
            if [ -f "$VIDEO_FILE" ] && [ -s "$VIDEO_FILE" ]; then
                echo "Video downloaded"
                local OEMBED=$(curl -s "https://www.tiktok.com/oembed?url=${TIKTOK_URL}" 2>&1)
                TITLE=$(echo "$OEMBED" | jq -r '.title // "TikTok Video"' 2>/dev/null)
                ARTIST=$(echo "$OEMBED" | jq -r '.author_name // "TikTok"' 2>/dev/null)
                return 0
            fi
        fi
    fi
    
    echo "All TikTok APIs failed"
    return 1
}

download_universal() {
    local url="$1"
    echo "=== Universal Downloader (yt-dlp) ==="
    
    local YTDLP_OPTS=""
    if echo "$url" | grep -q "instagram"; then
        echo "Platform: Instagram"
        if command -v chromium &> /dev/null; then
            YTDLP_OPTS="--cookies-from-browser chromium"
        fi
    elif echo "$url" | grep -q "youtube"; then
        echo "Platform: YouTube"
    elif echo "$url" | grep -q "soundcloud"; then
        echo "Platform: SoundCloud"
    else
        echo "Platform: Generic"
    fi
    
    echo "Fetching metadata..."
    local INFO=$(yt-dlp --dump-json --no-warnings $YTDLP_OPTS "$url" 2>&1 | grep -v "WARNING" | grep -v "ERROR" | head -n1)
    
    if [ -z "$INFO" ]; then
        echo "Failed to fetch metadata"
        return 1
    fi
    
    local IS_VIDEO=$(echo "$INFO" | jq -r 'if (.vcodec != "none" and .vcodec != null) then "true" else "false" end' 2>/dev/null || echo "false")
    local FILESIZE=$(echo "$INFO" | jq -r '.filesize // .filesize_approx // 0' 2>/dev/null || echo "0")
    
    echo "Type: $([ "$IS_VIDEO" = "true" ] && echo "Video" || echo "Audio")"
    echo "Size: $FILESIZE bytes"
    
    local MAX_VIDEO_SIZE=$((50 * 1024 * 1024))
    local DOWNLOAD_VIDEO="true"
    
    if [ "$FILESIZE" -gt "$MAX_VIDEO_SIZE" ]; then
        echo "File too large, audio only"
        DOWNLOAD_VIDEO="false"
    fi
    
    if [ "$IS_VIDEO" = "true" ] && [ "$DOWNLOAD_VIDEO" = "true" ]; then
        echo "Downloading video (720p max)..."
        yt-dlp -f "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best" \
            --merge-output-format mp4 \
            --write-info-json \
            $YTDLP_OPTS \
            -o "$DOWNLOAD_DIR/video.%(ext)s" \
            "$url" 2>&1
        
        VIDEO_FILE=$(ls "$DOWNLOAD_DIR"/*.mp4 2>/dev/null | head -n1)
        local INFO_JSON="$DOWNLOAD_DIR/video.info.json"
        
        if [ -f "$VIDEO_FILE" ]; then
            local REAL_SIZE=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || stat -f%z "$VIDEO_FILE" 2>/dev/null)
            echo "Downloaded: $REAL_SIZE bytes"
            
            if [ "$REAL_SIZE" -gt "$MAX_VIDEO_SIZE" ]; then
                echo "Too large, removing"
                rm -f "$VIDEO_FILE"
                VIDEO_FILE=""
            fi
        fi
    else
        echo "Downloading audio..."
        yt-dlp -x --audio-format mp3 --audio-quality 0 \
            --write-info-json \
            $YTDLP_OPTS \
            -o "$DOWNLOAD_DIR/audio.%(ext)s" \
            "$url" 2>&1
        
        local INFO_JSON="$DOWNLOAD_DIR/audio.info.json"
    fi
    
    if [ ! -f "$INFO_JSON" ]; then
        echo "Info JSON missing"
        return 1
    fi
    
    TITLE=$(jq -r '.title // "Unknown"' "$INFO_JSON" 2>/dev/null || echo "Unknown")
    ARTIST=$(jq -r '.uploader // .creator // .artist // "Unknown"' "$INFO_JSON" 2>/dev/null || echo "Unknown")
    local THUMB_URL=$(jq -r '.thumbnail // ""' "$INFO_JSON" 2>/dev/null || echo "")
    DURATION=$(jq -r '.duration // 0' "$INFO_JSON" 2>/dev/null || echo "0")
    
    echo "Title: $TITLE"
    echo "Artist: $ARTIST"
    
    if [ ! -z "$THUMB_URL" ] && [ "$THUMB_URL" != "null" ]; then
        echo "Downloading thumbnail..."
        THUMB_FILE="$DOWNLOAD_DIR/thumb.jpg"
        curl -s -L -o "$THUMB_FILE" "$THUMB_URL" 2>&1
        
        if [ ! -f "$THUMB_FILE" ] || [ ! -s "$THUMB_FILE" ]; then
            THUMB_FILE=""
        fi
    fi
    
    return 0
}

{
    echo "============================================"
    echo "MediaBot Downloader v1.0"
    echo "URL: $URL"
    echo "Time: $(date)"
    echo "============================================"
    
    if [ -z "$URL" ]; then
        error_exit "No URL provided"
    fi
    
    rm -f "$DOWNLOAD_DIR"/*.mp3 "$DOWNLOAD_DIR"/*.mp4 "$DOWNLOAD_DIR"/*.jpg "$DOWNLOAD_DIR"/*.json 2>/dev/null
    
    SUCCESS=0
    
    if echo "$URL" | grep -q "tiktok"; then
        if download_tiktok "$URL"; then
            SUCCESS=1
        else
            error_exit "TikTok download failed. Video may be private, age-restricted, or deleted."
        fi
    else
        if download_universal "$URL"; then
            SUCCESS=1
        else
            error_exit "Download failed. Check if URL is valid."
        fi
    fi
    
    AUDIO_TEMP=""
    if [ -f "$VIDEO_FILE" ] && [ -s "$VIDEO_FILE" ]; then
        echo "---"
        echo "Extracting audio track..."
        AUDIO_TEMP="$DOWNLOAD_DIR/audio_temp.mp3"
        
        if ffmpeg -y -i "$VIDEO_FILE" -vn -acodec libmp3lame -q:a 0 "$AUDIO_TEMP" 2>&1; then
            echo "Audio extracted"
        else
            echo "Audio extraction failed"
            AUDIO_TEMP=""
        fi
    else
        AUDIO_TEMP=$(ls "$DOWNLOAD_DIR"/*.mp3 2>/dev/null | head -n1)
    fi
    
    if [ -f "$AUDIO_TEMP" ] && [ -s "$AUDIO_TEMP" ]; then
        echo "---"
        echo "Adding metadata to audio..."
        
        SAFE_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 _-]/_/g' | head -c 100)
        AUDIO_OUTPUT="$DOWNLOAD_DIR/${SAFE_TITLE}.mp3"
        
        if [ -f "$THUMB_FILE" ] && [ -s "$THUMB_FILE" ]; then
            echo "Embedding cover art..."
            ffmpeg -y -i "$AUDIO_TEMP" -i "$THUMB_FILE" \
                -map 0:a -map 1:v \
                -c:a copy -c:v:0 mjpeg \
                -disposition:v:0 attached_pic \
                -id3v2_version 3 \
                -metadata title="$TITLE" \
                -metadata artist="$ARTIST" \
                "$AUDIO_OUTPUT" 2>&1 && echo "Cover embedded"
        else
            echo "Adding metadata (no cover)..."
            ffmpeg -y -i "$AUDIO_TEMP" \
                -c:a copy \
                -id3v2_version 3 \
                -metadata title="$TITLE" \
                -metadata artist="$ARTIST" \
                "$AUDIO_OUTPUT" 2>&1 && echo "Metadata added"
        fi
        
        if [ -f "$AUDIO_OUTPUT" ] && [ -s "$AUDIO_OUTPUT" ]; then
            [ "$AUDIO_TEMP" != "$AUDIO_OUTPUT" ] && rm -f "$AUDIO_TEMP"
            AUDIO_FILE="$AUDIO_OUTPUT"
            echo "Final audio: $(stat -c%s "$AUDIO_FILE" 2>/dev/null) bytes"
        fi
    fi
    
    rm -f "$DOWNLOAD_DIR"/*.json
    
    echo "============================================"
    echo "COMPLETED"
    echo "Video: $([ -f "$VIDEO_FILE" ] && echo "YES" || echo "NO")"
    echo "Audio: $([ -f "$AUDIO_FILE" ] && echo "YES" || echo "NO")"
    echo "============================================"
    
} >> "$LOG_FILE" 2>&1

jq -n \
    --arg video "$VIDEO_FILE" \
    --arg audio "$AUDIO_FILE" \
    --arg title "$TITLE" \
    --arg artist "$ARTIST" \
    --arg thumb "$THUMB_FILE" \
    --argjson duration "$DURATION" \
    '{
        video_path: $video,
        audio_path: $audio,
        title: $title,
        artist: $artist,
        thumb_path: $thumb,
        duration: $duration
    }'
