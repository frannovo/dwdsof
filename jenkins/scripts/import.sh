#!/bin/bash

export JIRA_BASE_URL="${JIRA_URL}"

export project_name="${JOB_BASE_NAME}"
export project_key="${project_key}"
export jira_id=1
export user="${USERNAME}"
export password="${PASSWORD}"
export defect_dojo_api_key="${TOKEN}"

if [ "$1" == "sonar" ]; then
    ${JENKINS_HOME}/scripts/dj-sonar-importer.sh
elif [ "$1" == "dependency-check" ]; then
    ${JENKINS_HOME}/scripts/dj-dependency-check-importer.sh
elif [ "$1" == "zap" ]; then
    ${JENKINS_HOME}/scripts/dj-zap-importer.sh
fi
