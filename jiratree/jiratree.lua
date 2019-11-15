local base64 = require "base64"

-- define the plugin functions as local functions
local function name()
  return "JiraTree"
end

local function version()
  return "1.0.0"
end

local menuItem
local function createMenus()
  -- get the menu root
  local menuRoot = vrLocalUserNode():find("ApplicationMenus/ContextMenu/Create")

  -- create the entry directly - Lua operates in unversioned metanode names.
  menuItem = vrCreateNode("ApplicationMenuEntry", "Jira Tree", menuRoot)
  menuItem.Caption = "Jira Tree"

  local conn = vrCreateNode("ApplicationMenuEntry", "Connection", menuItem)
  conn.Caption = "Connection"

  conn.Type = __ApplicationMenuEntry_TypeLua
  conn.Command = "context_create"
  conn.UserString = "JiraConnection"

  local proj = vrCreateNode("ApplicationMenuEntry", "Project", menuItem)
  proj.Caption = "Project"

  proj.Type = __ApplicationMenuEntry_TypeLua
  proj.Command = "context_create"
  proj.UserString = "JiraProject"
end


local function resume(co)
  local result, err = coroutine.resume(co)
  if not result then
    print(err)
  end
end

local function httpRequest(url, user, pass, callback)
  local co
  co = coroutine.create(function()
    -- Create the COM object.
    local web = luacom.CreateObject("MSXML2.XMLHTTP")

    local auth
    if user and pass then
      auth = "Basic " .. base64.enc(user .. ":" .. pass)
    end

    -- Make an asynchronous request.
    print("GET " .. url)
    web:open("GET", url, true)
    if auth then
      web:setRequestHeader("Authorization", auth)
    end
    web:send()

    -- Yield until done, or time out after 10 seconds.
    local timeout = 10
    local startTime = __Time
    while web.readyState < 4 and __Time - startTime < timeout do
      __deferredCall(function() resume(co) end, 0)
      coroutine.yield()
    end

    callback(web.status, web.responseText)
  end)
  resume(co)
end

-- makes multiple calls to the API to gather all issues matching the jql query
local function getAllIssues(jql, url, user, pass, completed, progress)
  local issues = {}
  local baseUrl = url .. "search?jql=" .. jql .. "&maxResults=-1"

  if not completed then
    error("getAllIssues requires a completion callback")
  end

  if not progress then
    progress = function(current, max) print("Progress " .. current .. "/" .. max) end
  end

  -- defining a reusable callback for the http request, so we can re-enter and get
  -- the next collection of results (if there are more than maxResults)
  local callback
  callback = function(status, response)
    print(response)
    local json = vrParseJSON(response)
    if json.errorMessages then
      for i, v in ipairs(json.errorMessages) do
        print(v)
      end
    elseif json.issues then
      local numIssues = #json.issues
      local startAt = json.startAt
      local total = json.total

      progress(startAt + numIssues, total)

      for _, v in ipairs(json.issues) do
        table.insert(issues, v)
      end

      if startAt + numIssues < total then
        httpRequest(baseUrl .. "&startAt=" .. tostring(startAt + numIssues), user, pass, callback)
      else
        completed(issues)
      end
    end
  end

  progress(0, -1)

  httpRequest(baseUrl, user, pass, callback)
end

local function addLabel(node, title, text)
  local mark = vrCreateNode("Annotation", node:getName(), node)
  mark.TargetAssembly = node

  local comment = vrCreateNode("AnnotationComment", "Comment", mark)
  comment.Comment = text
  comment.CreatedBy = title
end

-- populated with materials as they are encountered
local materials = {
}

-- map some colours to jira issue status
local colours = {}
colours["To Do"] = { 1.0, 1.0, 1.0 }
colours["In Progress"] = { 0.0, 0.0, 1.0 }
colours["Done"] = { 0.0, 1.0, 0.0 }

-- create an assembly representing a jira issue - with label and line drawn back to its parent
local function createIssueNode(parent, issue, angle, offset, scale, label)
  if not offset then offset = { 0, 0 } end
  if not scale then scale = 1 end
  if not label then label = false end
  local ep = vrCreateNode("Assembly", issue.key, parent)
  local vis = vrCreateShape("sphere", ep)
  local angle = math.rad(-90 + angle)
  ep.Transform.Position = {(math.sin(angle) + offset[1]) * scale, (math.cos(angle) + offset[2]) * scale, 0}
  vis.Transform.Scale = { 0.1, 0.1, 0.1 }

  if issue.fields.status then
    local status = issue.fields.status.name
    local material = materials[status]
    if not material then
      material = vrCreateNode("StdMaterial", status, vrTreeRoot().Libraries)
      material.Diffuse = colours[status] or { 1, 1, 1 }
      materials[status] = material
    end
    vis.Visual.Material = material
  end

  if parent ~= vrTreeRoot().Scenes then
    local spline = vrCreateNode("Spline", "Connector", parent)
    spline.DrawMode = 1
    vrCreateNode("Knot", "Knot", spline)
    local k2 = vrCreateNode("Knot", "Knot", spline)
    k2.Transform = ep.Transform
  end

  if label then
    addLabel(ep, issue.key, issue.fields.summary)
  end
  return ep
end

-- sort issues into types, and then process them per-epic
local function processIssues(node, issues)
  local byType = {}
  for i, v in ipairs(issues) do
    pcall(function()
      local type = v.fields.issuetype.name
      if not byType[type] then
        byType[type] = {}
      end
      table.insert(byType[type], v)
    end)
  end
  for k, v in pairs(byType) do
    print(k .. ":" .. #v)
  end

  local projectRef = node:child("MetaDataLink", "Project Root")
  if projectRef then
    vrDeleteNode(projectRef.Value)
    vrDeleteUnreferenced(vrTreeRoot().Libraries)
  else
    projectRef = vrCreateNode("MetaDataLink", "Project Root", node)
  end

  local projectNode = createIssueNode(vrTreeRoot().Scenes, { key = "Project Root - " .. node.Key, fields = { summary = "Jira Project" } }, 0, nil, 0, true)
  projectRef.Value = projectNode

  local epicNodes = {}
  local epics = byType["Epic"]
  epicNodes["none"] = createIssueNode(projectNode, { key = "No epic", fields = { summary = "Issues not assigned an epic" } }, 0, nil, 6, true)
  if epics and #epics > 0 then
    local step = 180 / #epics

    for i, epic in ipairs(epics) do
      epicNodes[epic.key] = createIssueNode(projectNode, epic, i * step, nil, 6, true)
    end
  end

  local byEpic = {}
  local sortEpic = function(issues)
    for _, v in ipairs(issues) do
      local epic = v.fields.customfield_10008 or "none"
      if not byEpic[epic] then
        byEpic[epic] = {}
      end
      table.insert(byEpic[epic], v)
    end
  end
  sortEpic(byType["Story"])
  sortEpic(byType["Task"])
  sortEpic(byType["Bug"])

  for k, v in pairs(byEpic) do
    local epicNode = epicNodes[k]
    -- todo create epic node somewhere if it doesnt exist (i.e. epic from different project)
    if epicNode and #v > 0 then
      local step = 360 / #v
      for i, issue in ipairs(v) do
        createIssueNode(epicNode, issue, i * step, nil, nil, true)
      end
    end
  end
end

local dirty = {}
local function projectPropChanged(node)
  dirty[node] = true
end

local function update()
  for k, v in pairs(dirty) do
    local node = k
    if node.Connection and string.len(node.Key) then
      local conn = node.Connection
      local jql = node.JQL
      if string.len(jql) == 0 then
        jql = "project=" .. node.Key
      end

      getAllIssues(jql, conn.URL, conn.Username, conn.APIToken, function(issues)
        processIssues(node, issues)
      end)
    end
  end
  dirty = {}
end

local function init()
  print("Init ", name())

  createMenus()

  vrAddPropertyObserver("jiratree-project-conn-observer", projectPropChanged, "JiraProject", "Connection")
  vrAddPropertyObserver("jiratree-project-key-observer", projectPropChanged, "JiraProject", "Key")
  vrAddPropertyObserver("jiratree-project-jql-observer", projectPropChanged, "JiraProject", "JQL")

  __registerCallback("onTimestepEvent", update)
end

local function cleanup()
  __unregisterCallback("onTimestepEvent", update)
  vrRemoveObserver("jiratree-project-conn-observer")
  vrRemoveObserver("jiratree-project-key-observer")
  vrRemoveObserver("jiratree-project-jql-observer")

  vrDeleteNode(menuItem)
end

function depends()
  return "JiraTree-Metanodes"
end

-- export the functions to the Lua state
return {
  name = name,
  version = version,
  init = init,
  cleanup = cleanup,
  depends = depends
}