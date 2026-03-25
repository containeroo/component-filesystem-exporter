local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.filesystem_exporter;
local instance = std.get(inv.parameters, '_instance', 'filesystem-exporter');
local distribution = std.get(std.get(inv.parameters, 'facts', {}), 'distribution', '');
local monitoring = import 'monitoring.jsonnet';
local resourceName = if params.name != null then params.name else instance;
local namespaceName = if params.namespace != null then params.namespace else 'syn-%s' % instance;

local optionalField(name, value) =
  if value == null then
    {}
  else if std.type(value) == 'object' then
    if std.length(std.objectFields(value)) == 0 then {} else { [name]: value }
  else if std.type(value) == 'array' then
    if std.length(value) == 0 then {} else { [name]: value }
  else
    { [name]: value };

local appLabels = {
  'app.kubernetes.io/name': resourceName,
  'app.kubernetes.io/component': 'exporter',
} + params.labels;

local image = '%s/%s:%s' % [
  params.image.registry,
  params.image.repository,
  params.image.tag,
];

local exporterArgs = [
  '-filesystem.path=%s' % params.filesystem.path,
  '-collector.interval=%s' % params.collector.interval,
  '-collector.timeout=%s' % params.collector.timeout,
  '-web.listen-address=%s' % params.web.listen_address,
  '-web.metrics-path=%s' % params.web.metrics_path,
] + params.extra_args;

local monitoringLabels =
  if std.member([ 'openshift4', 'oke' ], distribution) then
    {
      'openshift.io/cluster-monitoring': 'true',
    }
  else
    {
      SYNMonitoring: 'main',
    };
local monitoringNamespaceLabel =
  if !params.monitoring_enabled then
    {}
  else
    monitoringLabels;

local namespace =
  if params.monitoring_enabled && std.member(inv.applications, 'prometheus') then
    prometheus.RegisterNamespace(kube.Namespace(namespaceName)) {
      metadata+: {
        annotations+: params.namespace_annotations,
        labels+: monitoringNamespaceLabel + params.labels + params.namespace_labels,
      },
    }
  else
    kube.Namespace(namespaceName) {
      metadata+: {
        annotations+: params.namespace_annotations,
        labels+: monitoringNamespaceLabel + params.labels + params.namespace_labels,
      },
    };

local deployment = {
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: resourceName,
    namespace: namespaceName,
    labels: appLabels + params.deployment.labels,
    annotations: params.deployment.annotations,
  },
  spec: {
    replicas: params.replicas,
    selector: {
      matchLabels: appLabels,
    },
    template: {
      metadata: {
        labels: appLabels + params.pod_labels,
        annotations: params.pod_annotations,
      },
      spec:
        {
          terminationGracePeriodSeconds: params.termination_grace_period_seconds,
          containers: [
            {
              name: resourceName,
              image: image,
              imagePullPolicy: params.image.pull_policy,
              args: exporterArgs,
              ports: [
                {
                  name: params.service.port_name,
                  containerPort: params.service.port,
                },
              ],
              readinessProbe: params.readiness_probe,
              startupProbe: params.startup_probe,
              livenessProbe: params.liveness_probe,
              resources: params.resources,
              volumeMounts: params.volume_mounts,
            } + optionalField('securityContext', params.container_security_context),
          ],
          volumes: params.volumes,
        } + optionalField('priorityClassName', params.priority_class_name)
          + optionalField('imagePullSecrets', [ { name: name } for name in params.image_pull_secrets ])
          + optionalField('securityContext', params.pod_security_context)
          + optionalField('nodeSelector', params.node_selector)
          + optionalField('tolerations', params.tolerations)
          + optionalField('affinity', params.affinity),
    },
  },
};

local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: resourceName,
    namespace: namespaceName,
    labels: appLabels + params.service.labels,
    annotations: params.service.annotations,
  },
  spec: {
    selector: appLabels,
    ports: [
      {
        name: params.service.port_name,
        port: params.service.port,
        targetPort: params.service.port_name,
      },
    ],
  },
};

{
  [if params.create_namespace then '00_namespace']: namespace,
  '10_deployment': deployment,
  [if params.service.enabled then '20_service']: service,
  [if params.monitoring_enabled then '30_monitoring']: monitoring,
}
