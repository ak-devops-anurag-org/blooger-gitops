{{/* ===================================================================== */}}
{{/* Names                                                                  */}}
{{/* ===================================================================== */}}

{{- define "blooger.db.name" -}}
{{- .Values.naming.db | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "blooger.backend.name" -}}
{{- .Values.naming.backend | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "blooger.frontend.name" -}}
{{- .Values.naming.frontend | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "blooger.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/* ===================================================================== */}}
{{/* Labels                                                                 */}}
{{/* ===================================================================== */}}

{{/* Labels applied to every object. Not used as selectors. */}}
{{- define "blooger.labels" -}}
helm.sh/chart: {{ include "blooger.chart" . }}
app.kubernetes.io/part-of: blooger
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end -}}

{{/* Selector labels. Immutable across upgrades — never add anything here. */}}
{{- define "blooger.db.selectorLabels" -}}
app.kubernetes.io/name: {{ include "blooger.db.name" . }}
{{- end -}}

{{- define "blooger.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "blooger.backend.name" . }}
{{- end -}}

{{- define "blooger.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "blooger.frontend.name" . }}
{{- end -}}


{{/* ===================================================================== */}}
{{/* Database secret                                                        */}}
{{/* ===================================================================== */}}

{{/* Name of the Secret the DB and backend read their credentials from. */}}
{{- define "blooger.db.secretName" -}}
{{- if .Values.db.auth.existingSecret -}}
{{- .Values.db.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-secret" (include "blooger.db.name" .) -}}
{{- end -}}
{{- end -}}

{{/*
  Resolve the DB password. Order of preference:
    1. db.auth.password if the user set one
    2. the password already stored in the cluster (so `helm upgrade` is safe)
    3. a fresh random 24-char string
*/}}
{{- define "blooger.db.password" -}}
{{- if .Values.db.auth.password -}}
{{- .Values.db.auth.password -}}
{{- else -}}
{{- $secretName := printf "%s-secret" (include "blooger.db.name" .) -}}
{{- /* lookup returns an EMPTY MAP (not nil) when the object is absent, and it
       always returns empty during `helm template` / --dry-run. Both cases have
       to fall through to a fresh random password without dereferencing .data
       on something that has no such field. */ -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- $current := "" -}}
{{- if $existing -}}
{{- $current = index ($existing.data | default dict) "POSTGRES_PASSWORD" | default "" -}}
{{- end -}}
{{- if $current -}}
{{- $current | b64dec -}}
{{- else -}}
{{- randAlphaNum 24 -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{/* ===================================================================== */}}
{{/* Database PVC name                                                      */}}
{{/* ===================================================================== */}}

{{- define "blooger.db.claimName" -}}
{{- if .Values.db.persistence.pvc.existingClaim -}}
{{- .Values.db.persistence.pvc.existingClaim -}}
{{- else -}}
{{- printf "%s-pvc" (include "blooger.db.name" .) -}}
{{- end -}}
{{- end -}}


{{/* ===================================================================== */}}
{{/* Image reference                                                        */}}
{{/* ===================================================================== */}}

{{- define "blooger.image" -}}
{{- printf "%s:%s" .repository (.tag | toString) -}}
{{- end -}}
