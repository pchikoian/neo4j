{{/*
Expand the name of the chart.
*/}}
{{- define "neo4j.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "neo4j.fullname" -}}
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
{{- define "neo4j.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "neo4j.labels" -}}
helm.sh/chart: {{ include "neo4j.chart" . }}
{{ include "neo4j.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.commonLabels }}
{{ toYaml .Values.commonLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "neo4j.selectorLabels" -}}
app.kubernetes.io/name: {{ include "neo4j.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "neo4j.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "neo4j.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Neo4j image name
*/}}
{{- define "neo4j.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper image name (for the init container volume-permissions image)
*/}}
{{- define "neo4j.volumePermissions.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.volumePermissions.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "neo4j.imagePullSecrets" -}}
{{ include "common.images.pullSecrets" (dict "images" (list .Values.image .Values.volumePermissions.image) "global" .Values.global) }}
{{- end }}

{{/*
Create a default fully qualified configmap name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "neo4j.configmapName" -}}
{{- if .Values.existingConfigmap -}}
{{- printf "%s" (tpl .Values.existingConfigmap $) -}}
{{- else -}}
{{- printf "%s-configuration" (include "neo4j.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Return the Neo4j Secret Name
*/}}
{{- define "neo4j.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- printf "%s" .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s" (include "neo4j.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the Neo4j Secret Key
*/}}
{{- define "neo4j.secretPasswordKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecretPasswordKey }}
{{- printf "%s" .Values.auth.existingSecretPasswordKey }}
{{- else }}
{{- printf "neo4j-password" }}
{{- end }}
{{- end }}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "neo4j.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "neo4j.validateValues.replicaCount" .) -}}
{{- $messages := append $messages (include "neo4j.validateValues.auth" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate values of Neo4j - replica count
*/}}
{{- define "neo4j.validateValues.replicaCount" -}}
{{- if and (gt (int .Values.replicaCount) 1) (lt (int .Values.replicaCount) 3) -}}
neo4j: replicaCount
    Neo4j cluster requires at least 3 replicas to form a quorum, or use 1 for single instance.
    Please set replicaCount to 1 or >= 3.
{{- end -}}
{{- end -}}

{{/*
Validate values of Neo4j - auth
*/}}
{{- define "neo4j.validateValues.auth" -}}
{{- if and .Values.auth.enabled (not .Values.auth.neo4jPassword) (not .Values.auth.existingSecret) -}}
neo4j: auth.neo4jPassword
    A password is required when authentication is enabled.
    Please set auth.neo4jPassword or provide an existing secret.
{{- end -}}
{{- end -}}

{{/*
Get the namespace to deploy Neo4j based on namespaceOverride, .Release.Namespace or default to "default"
*/}}
{{- define "neo4j.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{/*
Return true if a configmap object should be created for Neo4j
*/}}
{{- define "neo4j.createConfigmap" -}}
{{- if not .Values.existingConfigmap }}
{{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if a secret object should be created for Neo4j
*/}}
{{- define "neo4j.createSecret" -}}
{{- if not .Values.auth.existingSecret }}
{{- true -}}
{{- end -}}
{{- end -}}

{{/*
Get the Kubernetes service name that will be used for cluster discovery
*/}}
{{- define "neo4j.serviceName" -}}
{{- printf "%s" (include "neo4j.fullname" .) -}}
{{- end -}}

{{/*
Get the headless service name that will be used for StatefulSet
*/}}
{{- define "neo4j.headlessServiceName" -}}
{{- printf "%s-headless" (include "neo4j.fullname" .) -}}
{{- end -}}

{{/*
Get the cluster service name that will be used for inter-cluster communication
*/}}
{{- define "neo4j.clusterServiceName" -}}
{{- printf "%s-cluster" (include "neo4j.fullname" .) -}}
{{- end -}}

{{/*
Return the volume permissions init container
*/}}
{{- define "neo4j.volumePermissionsInitContainer" -}}
- name: volume-permissions
  image: {{ include "neo4j.volumePermissions.image" . }}
  imagePullPolicy: {{ .Values.volumePermissions.image.pullPolicy | quote }}
  command:
    - /bin/bash
  args:
    - -ec
    - |
      mkdir -p {{ .Values.persistence.mountPath }}
      chown -R {{ .Values.containerSecurityContext.runAsUser }}:{{ .Values.podSecurityContext.fsGroup }} {{ .Values.persistence.mountPath }}
  {{- if .Values.volumePermissions.containerSecurityContext }}
  securityContext: {{- toYaml .Values.volumePermissions.containerSecurityContext | nindent 4 }}
  {{- end }}
  {{- if .Values.volumePermissions.resources }}
  resources: {{- toYaml .Values.volumePermissions.resources | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: data
      mountPath: {{ .Values.persistence.mountPath }}
{{- end -}}