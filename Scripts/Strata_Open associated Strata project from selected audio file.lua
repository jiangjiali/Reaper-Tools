--[[
  @description Strata_Open associated Strata project from selected audio file
  @author Audiokinetic
  @version 1.0.0-rc.1
  @changelog
    Initial release
  @provides
    [main=mediaexplorer] . https://raw.githubusercontent.com/audiokinetic/Reaper-Tools/$commit/Scripts/Strata_Open%20associated%20Strata%20project%20from%20selected%20audio%20file.lua
  @about
    The script opens up the associated Strata project for the currectly selected audio file in the Media Explorer.
  @license
    Copyright (c) 2022 AUDIOKINETIC Inc.

    The script in this file is licensed to use under the license available at:
    https://raw.githubusercontent.com/audiokinetic/Reaper-Tools/main/License.txt (the "License").
    You may not use this file except in compliance with the License.

    Unless required by applicable law or agreed to in writing, software distributed
    under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
    CONDITIONS OF ANY KIND, either express or implied.  See the License for the
    specific language governing permissions and limitations under the License.
]]--

-- constants --
local OK_RESULT = 1
local OK_MESSAGE_BOX = 0
local OK_CANCEL_MESSAGE_BOX = 1
local MEDIA_EXPLORER_ID = 1000
local MEDIA_EXPLORER_LIST_VIEW_ID = 1001
local MEDIA_EXPLORER_DIRECTORY_ID = 1002
local TRACK_VIEW_ID = 1000
local CURRENT_PROJECT = 0

-- global variables --
local SEPERATOR_CHAR = string.find(reaper.GetOS(), "Win") ~= nil and "\\" or "/"
local BROWSER_CMD = string.find(reaper.GetOS(), "OSX") ~= nil and "open" or "start"

-- helper functions --
local function openUrl(url)
  os.execute(BROWSER_CMD .. ' "" "' .. url .. '"')
end

local function getMetadata(pcmSource, list)
  for i = 1, #list do
    local _, candidate = reaper.GetMediaFileMetadata(pcmSource, list[i])

    if candidate and candidate ~= "" then
      return candidate
    end
  end

  return nil
end

-- dependancy checks --
if not reaper.JS_Window_FindChildByID or not reaper.JS_Localize or not reaper.JS_Window_Find or
  not reaper.JS_ListView_ListAllSelItems or not reaper.JS_Window_GetTitle or
  not reaper.JS_ListView_GetItemText or not reaper.JS_Window_SetScrollPos then
    local selectedOption = reaper.ShowMessageBox("The script requires the latest version of js_ReaScriptAPI be installed.\n\nView in ReaPack?", "Open In Strata: Failed", OK_CANCEL_MESSAGE_BOX)

    if selectedOption == OK_RESULT then
      if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages("js_ReaScriptAPI")
      else
        selectedOption = reaper.ShowMessageBox("Unable to locate ReaPack. You can download ReaPack by going to https://reapack.com.\n\nGo there m now?", "Open In Strata: Failed", OK_CANCEL_MESSAGE_BOX)

        if selectedOption == OK_RESULT then
          openUrl("https://reapack.com")
        end
      end
    end

    return
end

-- get selected items in media explorer --
local mediaExplorerWindow = reaper.OpenMediaExplorer("", false)

if not mediaExplorerWindow then
  reaper.ShowMessageBox("The script was not able to access the Media Explorer.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

local listView = reaper.JS_Window_FindChildByID(mediaExplorerWindow, MEDIA_EXPLORER_LIST_VIEW_ID)

if not listView then
  reaper.ShowMessageBox("The script was not able to access the Media Explorer File List.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

local count, indices = reaper.JS_ListView_ListAllSelItems(listView)

if count == 0 or not indices or indices == "" then
  reaper.ShowMessageBox("No file is selected in the Media Explorer File List.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

local directoryInputField = reaper.JS_Window_FindChildByID(mediaExplorerWindow, MEDIA_EXPLORER_DIRECTORY_ID)

if not directoryInputField then
  reaper.ShowMessageBox("The script was not able to access the Media Explorer Directory.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

local directory = reaper.JS_Window_GetTitle(directoryInputField)

indices = indices .. ","

local indexOfFirstComma = string.find(indices, ",")
local firstIndex = string.sub(indices, 0, indexOfFirstComma - 1)
local selectedFilename = reaper.JS_ListView_GetItemText(listView, tonumber(firstIndex), OK_MESSAGE_BOX)

local filePath = directory .. SEPERATOR_CHAR .. selectedFilename

-- Read data from wav header --
local pcmSource = reaper.PCM_Source_CreateFromFile(filePath)
local projectName = getMetadata(pcmSource, {"IXML:PROJECT", "IXML:Project", "IXML:project"})
local trackName = getMetadata(pcmSource, {"IXML:USER:trackName", "IXML:USER:TRACKNAME", "IXML:USER:TrackName", "IXML:USER:trackname"})
local regionName = getMetadata(pcmSource, {"ASWG:fxName", "ASWG:FXNAME", "ASWG:FxName", "ASWG:fxname"})

if not projectName then
  reaper.ShowMessageBox("IXML:PROJECT header missing or empty in selected file. The script expects the IXML:PROJECT header to container the associated project name.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

if not trackName then
  reaper.ShowMessageBox("IXML:USER:trackName header missing in selected file. The script expects the IXML:USER:trackName header to container the associated track name.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

if not regionName then
  reaper.ShowMessageBox("ASWG:fxName header missing in selected file. The script expects the ASWG:fxName header to container the associated region name.", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

local projectPath = nil
local directoryToSearchReverse = string.reverse(directory)
local nextProjectDirectory = directory
local nextSeperatorChar = 0

while true do
  nextProjectPath = nextProjectDirectory .. SEPERATOR_CHAR .. projectName .. ".rpp"

  if reaper.file_exists(nextProjectPath) then
    projectPath = nextProjectPath
    break
  end

  nextSeperatorChar = string.find(directoryToSearchReverse, SEPERATOR_CHAR, nextSeperatorChar + 1)

  if not nextSeperatorChar then
    break
  end

  nextProjectDirectory = string.sub(directory, 0, string.len(directory) - nextSeperatorChar)
end

if not projectPath then
  reaper.ShowMessageBox("Unable to locate project `" .. projectName .. "`", "Open In Strata: Failed", OK_MESSAGE_BOX)
  return
end

-- Open project and scroll to region --
reaper.Main_OnCommand(41929, 0) -- opens new project tab
reaper.Main_openProject("noprompt:" .. projectPath)

local markersAndRegions, _, _ = reaper.CountProjectMarkers(CURRENT_PROJECT)

local regionFound = false
for i = 0, markersAndRegions - 1 do
  local _, _, _, _, currentRegion, index, _ = reaper.EnumProjectMarkers3(0, i)

  if currentRegion == regionName then
    reaper.GoToRegion(0, index, true)
    regionFound = true
    break
  end
end

if not regionFound then
  reaper.ShowMessageBox("Unable move cursor to region `" .. regionName .. "`", "Open In Strata: Failed", OK_MESSAGE_BOX)
end

local trackView = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), TRACK_VIEW_ID)

reaper.Main_OnCommand(40297,0) -- deselect all tracks

local trackFound = false
for i = 0, reaper.CountTracks() - 1 do
  local currentTrack = reaper.GetTrack(CURRENT_PROJECT, i)
  local _, currentTrackName = reaper.GetTrackName(currentTrack)

  if currentTrackName == trackName then
    reaper.SetTrackSelected(currentTrack, true)

    -- Get Y postion of track and then scroll to it
    local yPosition = reaper.GetMediaTrackInfo_Value(currentTrack, "I_TCPY")
    reaper.JS_Window_SetScrollPos(trackView, "v", yPosition)

    trackFound = true
    break
  end
end

if not trackFound then
  reaper.ShowMessageBox("Unable to scroll view to track `" .. trackName .. "`", "Open In Strata: Failed", OK_MESSAGE_BOX)
end