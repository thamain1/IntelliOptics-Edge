{{/*
Expand the name of the chart.
*/}}
{{- define "IntelliOptics-edge-endpoint.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "IntelliOptics-edge-endpoint.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "IntelliOptics-edge-endpoint.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "IntelliOptics-edge-endpoint.labels" -}}
helm.sh/chart: {{ include "IntelliOptics-edge-endpoint.chart" . }}
{{ include "IntelliOptics-edge-endpoint.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "IntelliOptics-edge-endpoint.selectorLabels" -}}
app.kubernetes.io/name: {{ include "IntelliOptics-edge-endpoint.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "IntelliOptics-edge-endpoint.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "IntelliOptics-edge-endpoint.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
    We want to "own" the namespace we install into. This is a safety mechanism to ensure that
    can run the full lifecycle without getting tangled up with other stuff going on in the cluster.
*/}}
{{- define "validate.namespace" -}}
{{- $ns := lookup "v1" "Namespace" "" .Values.namespace }}
{{- if $ns }}
  {{- $helmOwner := index $ns.metadata.labels "app.kubernetes.io/managed-by" | default "" }}
  {{- $releaseName := index $ns.metadata.labels "app.kubernetes.io/instance" | default "" }}
  {{- if or (ne $helmOwner "Helm") (ne $releaseName .Release.Name) }}
    {{ fail (printf "❌ Error: Namespace '%s' already exists but is NOT owned by this Helm release ('%s'). Aborting deployment!" .Values.namespace .Release.Name) }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
  Determine the correct image tag to use for each container type. If the specific override
  is set for that image, use it. Otherwise, use the global image tag.
*/}}
{{- define "IntelliOptics-edge-endpoint.edgeEndpointTag" -}}
{{- .Values.edgeEndpointTag | default .Values.imageTag }}
{{- end }}

{{- define "IntelliOptics-edge-endpoint.inferenceTag" -}}
{{- .Values.inferenceTag | default .Values.imageTag }}
{{- end }}

{{/*
  Determine the correct pull policy to use for each container type. If it is 
  a dev tag, we use "Never" to avoid pulling from the registry. Otherwise,
  we use the global pull policy.
*/}}
{{- define "IntelliOptics-edge-endpoint.edgeEndpointPullPolicy" -}}
{{- $tag := include "IntelliOptics-edge-endpoint.edgeEndpointTag" . -}}
{{- if eq $tag "dev" -}}
Never
{{- else -}}
{{- default "IfNotPresent" .Values.imagePullPolicy -}}
{{- end -}}
{{- end -}}

{{- define "IntelliOptics-edge-endpoint.inferencePullPolicy" -}}
{{- $tag := include "IntelliOptics-edge-endpoint.inferenceTag" . -}}
{{- if eq $tag "dev" -}}
Never
{{- else -}}
{{- default "IfNotPresent" .Values.imagePullPolicy -}}
{{- end -}}
{{- end -}}

{{/*
  Get the edge-config.yaml file. If the user supplies one via `--set-file configFile=...yaml`
  then use that. Otherwise, use the default version in the `files/` directory. We define this
  as a function so that we can use it as a nonce to restart the pod when the config changes.
*/}}
{{- define "IntelliOptics-edge-endpoint.edgeConfig" -}}
{{- if .Values.configFile }}
{{- .Values.configFile }}
{{- else }}
{{- .Files.Get "files/default-edge-config.yaml" }}
{{- end }}
{{- end }}


