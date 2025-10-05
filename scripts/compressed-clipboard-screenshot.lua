-- Compressed Clipboard Screenshot Script for mpv
-- Captures the current frame, compresses it to ~200KB JPEG, and copies to clipboard
-- Requires: ffmpeg, osascript (macOS)

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- Configuration
local TEMP_DIR = os.getenv("TMPDIR") or "/tmp"
local JPEG_QUALITY = 85  -- JPEG quality (1-100), 85 gives good balance for ~200KB target

-- Helper function to generate unique temp filename
local function get_temp_filename()
  local timestamp = os.time()
  local random = math.random(1000, 9999)
  return utils.join_path(TEMP_DIR, string.format("mpv_screenshot_%d_%d.jpg", timestamp, random))
end

-- Helper function to show OSD messages
local function show_message(text, duration)
  duration = duration or 3
  mp.osd_message(text, duration)
  msg.info(text)
end

-- Helper function to cleanup temp file
local function cleanup_temp_file(filepath)
  if filepath and utils.file_info(filepath) then
    os.remove(filepath)
    msg.debug("Cleaned up temp file: " .. filepath)
  end
end

-- Main function to capture screenshot and copy to clipboard
local function compressed_clipboard_screenshot()
  show_message("📸 Capturing screenshot...", 2)

  -- Generate temp filename
  local temp_file = get_temp_filename()
  msg.info("Temp file: " .. temp_file)

  -- Take screenshot using mpv's built-in screenshot function
  -- Using "video" mode to capture without subtitles/OSD
  -- First save as PNG to temp location
  local temp_png = temp_file:gsub("%.jpg$", ".png")

  -- Use mpv's screenshot-to-file command
  local success = mp.commandv("screenshot-to-file", temp_png, "video")

  if not success then
    show_message("❌ Failed to capture screenshot", 3)
    return
  end

  -- Wait briefly for file to be written
  os.execute("sleep 0.1")

  -- Check if PNG was created
  if not utils.file_info(temp_png) then
    show_message("❌ Screenshot file not found", 3)
    return
  end

  msg.info("Screenshot captured: " .. temp_png)

  -- Compress PNG to JPEG using ffmpeg
  -- Target file size: ~200KB
  -- Strategy: Use JPEG quality 85 and scale if needed
  local ffmpeg_args = {
    "ffmpeg",
    "-i", temp_png,
    "-vf", "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease",  -- Limit resolution
    "-q:v", tostring(JPEG_QUALITY),
    "-y",  -- Overwrite output file
    temp_file
  }

  msg.info("Compressing with ffmpeg: " .. table.concat(ffmpeg_args, " "))
  local compress_result = utils.subprocess({
    args = ffmpeg_args,
    cancellable = false
  })

  if compress_result.status ~= 0 then
    show_message("❌ Failed to compress screenshot", 3)
    msg.error("ffmpeg error: " .. (compress_result.stderr or "unknown"))
    cleanup_temp_file(temp_png)
    return
  end

  -- Check compressed file size
  local file_info = utils.file_info(temp_file)
  if not file_info then
    show_message("❌ Compressed file not found", 3)
    cleanup_temp_file(temp_png)
    return
  end

  local file_size_kb = math.floor(file_info.size / 1024)
  msg.info(string.format("Compressed file size: %d KB", file_size_kb))

  -- If file is still too large (>300KB), reduce quality further
  if file_size_kb > 300 then
    msg.info("File too large, reducing quality...")
    local lower_quality = math.max(70, JPEG_QUALITY - 15)
    local ffmpeg_args_retry = {
      "ffmpeg",
      "-i", temp_png,
      "-vf", "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease",
      "-q:v", tostring(lower_quality),
      "-y",
      temp_file
    }

    compress_result = utils.subprocess({
      args = ffmpeg_args_retry,
      cancellable = false
    })

    if compress_result.status == 0 then
      file_info = utils.file_info(temp_file)
      if file_info then
        file_size_kb = math.floor(file_info.size / 1024)
        msg.info(string.format("Re-compressed file size: %d KB", file_size_kb))
      end
    end
  end

  -- Copy to clipboard using osascript (macOS)
  local osascript_cmd = string.format([[
    osascript -e 'set the clipboard to (read (POSIX file "%s") as JPEG picture)'
  ]], temp_file)

  msg.info("Copying to clipboard...")
  local clipboard_result = os.execute(osascript_cmd)

  -- Cleanup temp files
  cleanup_temp_file(temp_png)
  cleanup_temp_file(temp_file)

  if clipboard_result == 0 or clipboard_result == true then
    show_message(string.format("✅ Screenshot copied to clipboard (%d KB)", file_size_kb), 3)
  else
    show_message("❌ Failed to copy to clipboard", 3)
    msg.error("osascript failed")
  end
end

-- Register the script binding
mp.add_key_binding(nil, "compressed-clipboard-screenshot", compressed_clipboard_screenshot)

msg.info("Compressed Clipboard Screenshot script loaded")
