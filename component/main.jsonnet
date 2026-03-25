local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.filesystem_exporter;
local instance = std.get(inv.parameters, '_instance', 'filesystem-exporter');
local distribution = std.get(std.get(inv.parameters, 'facts', {}), 'distribution', '');
local monitoring = import 'monitoring.jsonnet';
local resourceName = instance;
local namespaceName = params.namespace;
local filesystemPath = '/data';
local image = '%s/%s:%s' % [
  params.images.exporter.registry,
  params.images.exporter.repository,
  params.images.exporter.tag,
];
local appLabels = {
  'app.kubernetes.io/name': resourceName,
  'app.kubernetes.io/component': 'exporter',
  filesystem_exporter_instance: resourceName,
};
local exporterArgs = [
  '-filesystem.path=%s' % filesystemPath,
  '-collector.interval=5m',
  '-collector.timeout=2m',
  '-web.listen-address=:9799',
  '-web.metrics-path=/metrics',
];
local resources = {
  requests: {
    cpu: '100m',
    memory: '128Mi',
  },
  limits: {
    memory: '512Mi',
  },
};

local volume =
  if params.volume == null || std.length(std.objectFields(params.volume)) == 0 then
    error 'filesystem_exporter.volume is required and must contain exactly one Kubernetes volume source'
  else
    { name: 'data' } + params.volume;

local volumeMount = {
  name: 'data',
  mountPath: filesystemPath,
  readOnly: true,
};

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
        labels+: monitoringNamespaceLabel,
      },
    }
  else
    kube.Namespace(namespaceName) {
      metadata+: {
        labels+: monitoringNamespaceLabel,
      },
    };

local deployment = {
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: resourceName,
    namespace: namespaceName,
    labels: appLabels,
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: appLabels,
    },
    template: {
      metadata: {
        labels: appLabels,
      },
      spec:
        {
          terminationGracePeriodSeconds: 30,
          containers: [
            {
              name: resourceName,
              image: image,
              imagePullPolicy: 'IfNotPresent',
              args: exporterArgs,
              ports: [
                {
                  name: 'http-metrics',
                  containerPort: 9799,
                },
              ],
              readinessProbe: {
                httpGet: {
                  path: '/-/ready',
                  port: 'http-metrics',
                },
              },
              startupProbe: {
                httpGet: {
                  path: '/-/healthy',
                  port: 'http-metrics',
                },
                periodSeconds: 5,
                failureThreshold: 60,
              },
              livenessProbe: {
                httpGet: {
                  path: '/-/healthy',
                  port: 'http-metrics',
                },
              },
              resources: resources,
              volumeMounts: [ volumeMount ],
            },
          ],
          volumes: [ volume ],
        },
    },
  },
};

local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: resourceName,
    namespace: namespaceName,
    labels: appLabels,
  },
  spec: {
    selector: appLabels,
    ports: [
      {
        name: 'http-metrics',
        port: 9799,
        targetPort: 'http-metrics',
      },
    ],
  },
};

{
  '00_namespace': namespace,
  '10_deployment': deployment,
  '20_service': service,
  [if params.monitoring_enabled then '30_monitoring']: monitoring,
}
