local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.filesystem_exporter;
local instance = std.get(inv.parameters, '_instance', 'filesystem-exporter');
local resourceName = instance;
local namespaceName = params.namespace;
local grafanaDashboardName = instance;

local alertlabels = {
  syn: 'true',
  syn_component: 'filesystem-exporter',
};

local formatRatio(value) = '%g' % value;
local formatPercent(value) = '%g%%' % (value * 100);

local defaultMonitoringAlerts = {
  FilesystemExporterCollectionFailing: {
    expr: 'max_over_time(filesystem_exporter_collect_success{root_path="%s"}[%s]) < 1' % [
      params.filesystem.path,
      '10m',
    ],
    'for': '10m',
    labels: {
      severity: 'warning',
    },
    annotations: {
      summary: 'filesystem-exporter has not completed a successful collection',
      description: 'filesystem-exporter for {{ $labels.root_path }} has failed every collection for the last 10m.',
    },
  },
  FilesystemExporterCollectionStale: {
    expr: 'time() - filesystem_exporter_collect_timestamp_seconds{root_path="%s"} > %d' % [
      params.filesystem.path,
      900,
    ],
    'for': '5m',
    labels: {
      severity: 'warning',
    },
    annotations: {
      summary: 'filesystem-exporter metrics are stale',
      description: 'filesystem-exporter for {{ $labels.root_path }} has not produced a fresh collection timestamp for more than 900 seconds.',
    },
  },
  FilesystemUsageHigh: {
    expr: 'filesystem_path_available_bytes{root_path="%s",path="%s"} / filesystem_path_capacity_bytes{root_path="%s",path="%s"} < %s' % [
      params.filesystem.path,
      params.filesystem.path,
      params.filesystem.path,
      params.filesystem.path,
      formatRatio(0.1),
    ],
    'for': '15m',
    labels: {
      severity: 'warning',
    },
    annotations: {
      summary: 'filesystem free space is low',
      description: 'Less than %s free space remains on {{ $labels.path }}.' % formatPercent(0.1),
    },
  },
  FilesystemUsageCritical: {
    expr: 'filesystem_path_available_bytes{root_path="%s",path="%s"} / filesystem_path_capacity_bytes{root_path="%s",path="%s"} < %s' % [
      params.filesystem.path,
      params.filesystem.path,
      params.filesystem.path,
      params.filesystem.path,
      formatRatio(0.05),
    ],
    'for': '15m',
    labels: {
      severity: 'critical',
    },
    annotations: {
      summary: 'filesystem free space is critically low',
      description: 'Less than %s free space remains on {{ $labels.path }}.' % formatPercent(0.05),
    },
  },
};

local grafanaDashboard = com.namespaced(namespaceName, kube.ConfigMap('%s-dashboard' % resourceName) {
  metadata+: {
    labels+: {
      grafana_dashboard: '1',
    },
  },
  data: {
    ['%s.json' % grafanaDashboardName]: std.manifestJsonEx(
      {
        annotations: {
          list: [
            {
              builtIn: 1,
              datasource: {
                type: 'grafana',
                uid: '-- Grafana --',
              },
              enable: true,
              hide: true,
              iconColor: 'rgba(0, 211, 255, 1)',
              name: 'Annotations & Alerts',
              type: 'dashboard',
            },
          ],
        },
        editable: true,
        graphTooltip: 0,
        id: null,
        links: [],
        panels: [
          {
            datasource: {
              type: 'prometheus',
              uid: '${datasource}',
            },
            fieldConfig: {
              defaults: {
                color: {
                  mode: 'palette-classic',
                },
                custom: {
                  axisBorderShow: false,
                  axisCenteredZero: false,
                  axisColorMode: 'text',
                  drawStyle: 'line',
                  fillOpacity: 10,
                  lineInterpolation: 'linear',
                  lineWidth: 2,
                  pointSize: 4,
                  showPoints: 'never',
                  spanNulls: false,
                  stacking: {
                    group: 'A',
                    mode: 'none',
                  },
                },
                unit: 'bytes',
              },
              overrides: [],
            },
            gridPos: {
              h: 8,
              w: 16,
              x: 0,
              y: 0,
            },
            id: 1,
            options: {
              legend: {
                calcs: [],
                displayMode: 'list',
                placement: 'bottom',
              },
              tooltip: {
                mode: 'multi',
                sort: 'none',
              },
            },
            targets: [
              {
                expr: 'filesystem_path_used_bytes{root_path=~"$root_path",path=~"$root_path"}',
                legendFormat: 'used',
                refId: 'A',
              },
              {
                expr: 'filesystem_path_available_bytes{root_path=~"$root_path",path=~"$root_path"}',
                legendFormat: 'available',
                refId: 'B',
              },
              {
                expr: 'filesystem_path_capacity_bytes{root_path=~"$root_path",path=~"$root_path"}',
                legendFormat: 'capacity',
                refId: 'C',
              },
            ],
            title: 'Root Filesystem Capacity',
            type: 'timeseries',
          },
          {
            datasource: {
              type: 'prometheus',
              uid: '${datasource}',
            },
            fieldConfig: {
              defaults: {
                color: {
                  mode: 'thresholds',
                },
                decimals: 1,
                max: 1,
                min: 0,
                thresholds: {
                  mode: 'absolute',
                  steps: [
                    {
                      color: 'red',
                      value: null,
                    },
                    {
                      color: 'yellow',
                      value: 0.1,
                    },
                    {
                      color: 'green',
                      value: 0.2,
                    },
                  ],
                },
                unit: 'percentunit',
              },
              overrides: [],
            },
            gridPos: {
              h: 8,
              w: 8,
              x: 16,
              y: 0,
            },
            id: 2,
            options: {
              colorMode: 'background',
              graphMode: 'none',
              justifyMode: 'auto',
              orientation: 'auto',
              reduceOptions: {
                calcs: [ 'lastNotNull' ],
                fields: '',
                values: false,
              },
              textMode: 'auto',
            },
            targets: [
              {
                expr: 'filesystem_path_available_bytes{root_path=~"$root_path",path=~"$root_path"} / filesystem_path_capacity_bytes{root_path=~"$root_path",path=~"$root_path"}',
                legendFormat: 'free ratio',
                refId: 'A',
              },
            ],
            title: 'Free Space',
            type: 'stat',
          },
          {
            datasource: {
              type: 'prometheus',
              uid: '${datasource}',
            },
            fieldConfig: {
              defaults: {
                color: {
                  mode: 'palette-classic',
                },
                custom: {
                  axisBorderShow: false,
                  axisCenteredZero: false,
                  axisColorMode: 'text',
                  drawStyle: 'bars',
                  fillOpacity: 80,
                  lineWidth: 1,
                  showPoints: 'never',
                  stacking: {
                    group: 'A',
                    mode: 'none',
                  },
                },
                unit: 'bytes',
              },
              overrides: [],
            },
            gridPos: {
              h: 9,
              w: 24,
              x: 0,
              y: 8,
            },
            id: 3,
            options: {
              legend: {
                calcs: [],
                displayMode: 'table',
                placement: 'right',
              },
              tooltip: {
                mode: 'single',
                sort: 'none',
              },
            },
            targets: [
              {
                expr: 'sort_desc(filesystem_path_used_bytes{root_path=~"$root_path",path!="$root_path"})',
                legendFormat: '{{ path }}',
                refId: 'A',
              },
            ],
            title: 'Immediate Child Directories by Used Space',
            type: 'timeseries',
          },
          {
            datasource: {
              type: 'prometheus',
              uid: '${datasource}',
            },
            fieldConfig: {
              defaults: {
                color: {
                  mode: 'palette-classic',
                },
                custom: {
                  axisBorderShow: false,
                  axisCenteredZero: false,
                  axisColorMode: 'text',
                  drawStyle: 'line',
                  fillOpacity: 15,
                  lineWidth: 2,
                  showPoints: 'never',
                  stacking: {
                    group: 'A',
                    mode: 'none',
                  },
                },
                unit: 's',
              },
              overrides: [],
            },
            gridPos: {
              h: 8,
              w: 12,
              x: 0,
              y: 17,
            },
            id: 4,
            options: {
              legend: {
                calcs: [],
                displayMode: 'list',
                placement: 'bottom',
              },
              tooltip: {
                mode: 'multi',
                sort: 'none',
              },
            },
            targets: [
              {
                expr: 'filesystem_exporter_collect_duration_seconds{root_path=~"$root_path"}',
                legendFormat: 'collect duration',
                refId: 'A',
              },
            ],
            title: 'Collection Duration',
            type: 'timeseries',
          },
          {
            datasource: {
              type: 'prometheus',
              uid: '${datasource}',
            },
            fieldConfig: {
              defaults: {
                color: {
                  mode: 'thresholds',
                },
                max: 1,
                min: 0,
                thresholds: {
                  mode: 'absolute',
                  steps: [
                    {
                      color: 'red',
                      value: null,
                    },
                    {
                      color: 'green',
                      value: 1,
                    },
                  ],
                },
                unit: 'none',
              },
              overrides: [],
            },
            gridPos: {
              h: 8,
              w: 12,
              x: 12,
              y: 17,
            },
            id: 5,
            options: {
              colorMode: 'background',
              graphMode: 'none',
              justifyMode: 'auto',
              orientation: 'auto',
              reduceOptions: {
                calcs: [ 'lastNotNull' ],
                fields: '',
                values: false,
              },
              textMode: 'auto',
            },
            targets: [
              {
                expr: 'filesystem_exporter_collect_success{root_path=~"$root_path"}',
                legendFormat: 'collect success',
                refId: 'A',
              },
            ],
            title: 'Last Collection Success',
            type: 'stat',
          },
        ],
        refresh: '30s',
        schemaVersion: 39,
        style: 'dark',
        tags: [ 'filesystem-exporter', 'storage', 'prometheus' ],
        templating: {
          list: [
            {
              current: {
                selected: false,
                text: 'Prometheus',
                value: 'Prometheus',
              },
              hide: 0,
              includeAll: false,
              label: 'Datasource',
              multi: false,
              name: 'datasource',
              options: [],
              query: 'prometheus',
              refresh: 1,
              regex: '',
              skipUrlSync: false,
              type: 'datasource',
            },
            {
              current: {
                selected: false,
                text: params.filesystem.path,
                value: params.filesystem.path,
              },
              datasource: {
                type: 'prometheus',
                uid: '${datasource}',
              },
              definition: 'label_values(filesystem_path_used_bytes, root_path)',
              hide: 0,
              includeAll: false,
              label: 'Root Path',
              multi: false,
              name: 'root_path',
              options: [],
              query: {
                query: 'label_values(filesystem_path_used_bytes, root_path)',
                refId: 'filesystem-exporter-root-paths',
              },
              refresh: 1,
              regex: '',
              skipUrlSync: false,
              sort: 1,
              type: 'query',
            },
          ],
        },
        time: {
          from: 'now-24h',
          to: 'now',
        },
        timepicker: {},
        timezone: '',
        title: 'Filesystem Exporter',
        uid: 'filesystem-exporter',
        version: 1,
      },
      '  '
    ),
  },
});

local serviceMonitor = com.namespaced(namespaceName, {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    labels: {
      'app.kubernetes.io/name': resourceName,
      'app.kubernetes.io/component': 'exporter',
      prometheus: 'main',
    },
    name: resourceName,
  },
  spec: {
    endpoints: [
      {
        interval: '30s',
        port: 'http-metrics',
        path: '/metrics',
      },
    ],
    namespaceSelector: {
      matchNames: [ namespaceName ],
    },
    selector: {
      matchLabels: {
        'app.kubernetes.io/name': resourceName,
        'app.kubernetes.io/component': 'exporter',
      },
    },
  },
});

local alertRules = com.namespaced(namespaceName, {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: resourceName,
    labels: {
      prometheus: 'main',
      role: 'alert-rules',
    },
  },
  spec: {
    groups: [
      {
        name: '%s.rules' % resourceName,
        rules: [
          defaultMonitoringAlerts[field] {
            alert: field,
            labels+: alertlabels,
          }
          for field in std.sort(std.objectFields(defaultMonitoringAlerts))
        ],
      },
    ],
  },
});

local finalAlertRules =
  if std.member(inv.applications, 'prometheus') then
    prometheus.Enable(alertRules)
  else
    alertRules;

local finalServiceMonitor =
  if std.member(inv.applications, 'prometheus') then
    prometheus.Enable(serviceMonitor)
  else
    serviceMonitor;

[
  finalAlertRules,
  finalServiceMonitor,
] + if params.grafana_dashboard.enabled then [ grafanaDashboard ] else []
