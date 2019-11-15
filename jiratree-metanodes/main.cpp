// main.cpp
#include <vrtree_api.h>
using namespace vrtree_cpp;

#include <cassert>

// Implement all of the standard API functions for api versioning, 
// and other hooks such as logging and progress displays
VRPLUGIN_API_IMPL;

PLUGIN_ENTRY_POINT const char* VRTREE_APIENTRY VRPName()
{
  return "JiraTree-Metanodes";
}

PLUGIN_ENTRY_POINT const char* VRTREE_APIENTRY VRPVersion()
{
  return "1.0.0";
}

static void registerMetaNodes()
{
  HMeta jiraConnection = VRCreateMetaNode("JiraConnection");
  VRAddPropertyString(jiraConnection, "URL"); // url to jira instance api (e.g. site.atlassian.net/rest/api/2/)
  VRAddPropertyString(jiraConnection, "Username");
  VRAddPropertyString(jiraConnection, "APIToken");
  assert(VRFinishMetaNode(jiraConnection) == 0);

  HMeta jiraProject = VRCreateMetaNode("JiraProject");
  VRAddPropertyLinkFilter(jiraProject, "Connection", "JiraConnection");
  VRAddPropertyString(jiraProject, "Key");
  VRAddPropertyString(jiraProject, "JQL"); // JQL to replace default query
  assert(VRFinishMetaNode(jiraProject) == 0);
}

// Implement VRPInit to respond to application startup
PLUGIN_ENTRY_POINT int VRTREE_APIENTRY VRPInit()
{
  // load all of the VRTree C API functions. Note that a valid API license is required.
  VRPLUGIN_LOADVRTREE;

  registerMetaNodes();

  return 0;
}

// Implement VRPCleanup to respond to unloading of the plugin
PLUGIN_ENTRY_POINT int VRTREE_APIENTRY VRPCleanup()
{
  return 0;
}

// Insert API license XML here
PLUGIN_ENTRY_POINT const char* VRTREE_APIENTRY VRPSignature()
{
  return "<VRTREE_API><company>Virtalis</company><feature>jiratree.dll</feature><feature>JiraTree-Metanodes</feature><feature>SCC_PLUGIN</feature></VRTREE_API>560900f5981b0b3d471cb7ad18fbbceec046f5b749869ce0c2dc161f5df3776b15ac616c14b2b513f1212c3b328553768eaf921a0aa6d55b6a03501e07707f8deea702a71de5a1fe0f958cf4611102c10a9e317060e0218e201de9e1ccb3743b0f67c818557d6d311694c6dfc0d2d3b8847ce578ac667ca1583d2f50b770c227";
}
  