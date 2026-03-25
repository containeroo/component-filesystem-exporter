local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.filesystem_exporter;
local instance = std.get(inv.parameters, '_instance', 'filesystem-exporter');
local argocd = import 'lib/argocd.libjsonnet';
local namespace = if params.namespace != null then params.namespace else 'syn-%s' % instance;

local app = argocd.App(instance, namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/%s' % [appPath, instance]]: app,
}
