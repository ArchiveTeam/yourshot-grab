dofile("table_show.lua")
dofile("urlcode.lua")
dofile("base64.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://m%.yourshot%.nationalgeographic%.com/")
      or string.match(url, "/images/apple%-touch%-icon[^%.]*%.png$")
      or string.match(url, "/images/favicon%.ico$")
      or string.match(url, "/text/xml%+oembed%?url=")
      or string.match(url, "/application/json%+oembed%?url=")
      or string.match(url, "^https?://yourshot%.nationalgeographic%.com/photos/[0-9]+$") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://data%.livefyre%.com/") then
    return true
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if ids[s] then
      return true
    end
  end

  for s in string.gmatch(url, "([a-zA-Z0-9_%-]+)") do
    if ids[s] then
      return true
    end
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://yourshot%.nationalgeographic%.com/static/")
      or string.match(url, "^https?://fonts%.ngeo%.com") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
      and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^https?:\\u002F\\u002F") then
      check(string.gsub(newurl, "\\u002F", "/"))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if allowed(url, nil) and status_code ~= 404 and status_code ~= 403
      and not string.match(url, "^https?://yourshot%.nationalgeographic%.com/u/") then
    html = read_file(file)
    local match
    if string.match(url, "^https?://yourshot%.nationalgeographic%.com/photos/[0-9]+/$") then
      local photo = string.match(url, "/([0-9]+)/$")
      local photo_base64 = base64enc("PHOTO_" .. photo)
      local fyre_site_id = string.match(html, "\"siteId\":%s+Number%('([0-9]+)'%)")
      check("https://yourshot.nationalgeographic.com/rpc/photo-read/" .. photo .. "/")
      --check("https://yourshot.nationalgeographic.com/rpc/photo-ratings/" .. photo .. "/")
      --check("https://yourshot.nationalgeographic.com/rpc/photo-read-user-data/" .. photo .. "/")
      check("https://data.livefyre.com/bs3/v3.1/natgeo.fyre.co/" .. fyre_site_id .. "/" .. photo_base64 .. "/init")
      check("https://data.livefyre.com/bs3/v3.1/natgeo.fyre.co/" .. fyre_site_id .. "/" .. photo_base64 .. "/0.json")
    end
    local image_size = 0
    local image_largest = ""
    local image_largest_id = ""
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      if string.match(url, "^https?://data%.livefyre%.com/")
          and string.match(newurl, "^/natgeo%.fyre%.co/") then
        check("https://data.livefyre.com/bs3/v3.1" .. newurl)
      elseif string.match(newurl, "/ [0-9]+w$") then
        local size = tonumber(string.match(newurl, "([0-9]+)w$"))
        local newurl_stripped = string.match(newurl, "^([^%s]+)")
        local newurl_id = string.match(newurl_stripped, "([a-zA-Z0-9_%-]+)/$")
        if size > image_size then
          image_size = size
          image_largest = newurl_stripped
          image_largest_id = newurl_id
        end
      else
        checknewurl(newurl)
      end
      if image_largest ~= "" then
        ids[image_largest_id] = true
        checknewurl(image_largest)
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  if http_stat["rderrmsg"] ~= nil then
    io.stdout:write(url_count .. "=" .. status_code .. " " .. http_stat["rderrmsg"] .. " " .. url["url"] .. "  \n")
  else
    io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  end
  io.stdout:flush()

  if string.match(url["url"], "^https?://yourshot%.nationalgeographic%.com/photos/([0-9]+)/$") then
    ids[string.match(url["url"], "/([0-9]+)/$")] = true
  end

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true then
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
