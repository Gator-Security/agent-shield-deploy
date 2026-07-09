{{- define "agent-shield.labels" -}}
app.kubernetes.io/part-of: agent-shield
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}
