#!/bin/bash

source ${JENKINS_HOME}/scripts/common.sh

ensure_vars project_name \
	user \
	password \
	defect_dojo_api_key \
	SONAR_URL

DEFECT_DOJO_TEST_TYPE=${DEFECT_DOJO_TEST_TYPE-"Generic Findings Import"}

OUTFILE=${OUTFILE-outfile.csv}
declare -A SONAR_SEVERITY_MAPPING=( [BLOCKER]=Critical [CRITICAL]=High [MAJOR]=Medium [MINOR]=Low )

clean_description() {
	jq -r '.rule.htmlDesc' <<<$1 \
		| sed -n '0,/^<b>References<\/b><br\/>$/ p'  \
		| grep -v '<b>References</b>' \
		| sed -n '0,/^<h2>See<\/h2>$/ p'  \
		| grep -v '<h2>See</h2>' \
		| sed -e 's#<br />#\\n#g;s#<p>#\\n#g;s#<\/p>#\\n#g;s#<br/>#\\n#g' \
		-e 's#<ul>##g;s#<\/ul>##g;s#<li>##g;s#<\/li>##g;s#<b>##g;s#<\/b>##g;s#<h2>##g;s#<\/h2>##g' \
		-e 's#<code>##g;s#<\/code>##g;s#&nbsp;# #g;s#\"##g' \
		-e 's#<pre>#\`\`\`\\n#g;s#<\/pre>#\\n\`\`\`#g'
}

print_open_issues() {
	local IFS=$'\n'
	if ! JSON_BLOB=$(curl_json_get "${SONAR_API_URL}/issues/search?componentKeys=${1}&types=VULNERABILITY" -u $sonar_user:$sonar_user_password); then		
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Unable to find componentKey ${1} in sonar." <<< "$JSON_BLOB"			
		
	fi
	SONAR_COMPONENT_ISSUES=$(jq -r '.issues[] | select( (.status == "OPEN") ) | .key' <<< $JSON_BLOB)
	for SONAR_ISSUE_ID in $SONAR_COMPONENT_ISSUES; do
		if ! JSON_BLOB=$(curl_json_get "${SONAR_API_URL}/issues/search?issues=${SONAR_ISSUE_ID}" -u $sonar_user:$sonar_user_password); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Unable to find issue with ID ${SONAR_ISSUE_ID}" <<< "$JSON_BLOB"			
		fi
		SONAR_ISSUE_INFO=$(jq -r '.issues[0]' <<< $JSON_BLOB)
		CREATION_DATE=$(jq -r '.creationDate' <<< $SONAR_ISSUE_INFO)
		TITLE=$(jq -r '.message' <<< $SONAR_ISSUE_INFO)
		COMPONENT=$(jq -r '.component' <<< $SONAR_ISSUE_INFO)
		LINE=$(jq -r '.line' <<< $SONAR_ISSUE_INFO)
		RULE_ID=$(jq -r '.rule' <<< $SONAR_ISSUE_INFO)

		if ! RULE_INFO=$(curl_json_get "${SONAR_API_URL}/rules/show?key=${RULE_ID}" -u $sonar_user:$sonar_user_password); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Unable to find rule ${RULE_ID}." <<< "$JSON_BLOB"
		fi

		REFERENCES=""
		CWE_ID="0"
		for CWE_LINK in $(echo "${RULE_INFO}" | jq -r '.rule.htmlDesc' | grep CWE-); do
			CWE_ID=$(echo "${CWE_LINK}" | sed -n -e 's/.*<a .*>.*CWE-\([[:alnum:]]\+\)[\:]*.*/\1/p')
		done

		SEVERITY=${SONAR_SEVERITY_MAPPING[$(echo ${RULE_INFO} | jq -r '.rule.severity')]}
		RULE_DESCRIPTION=$(clean_description "${RULE_INFO}")
		DESCRIPTION=$"Issue found on ${COMPONENT} at line ${LINE}"\\n"${RULE_DESCRIPTION}"
		for REFERENCE in $(echo ${RULE_INFO} | jq -r '.rule.htmlDesc' | sed -n '/^<b>References<\/b><br\/>$/,$p' | grep href); do
			REFERENCE_NAME=$(echo "${REFERENCE}" | sed -n 's:.*<a .*>\(.*\)</a>.*:\1:p')
			REFERENCE_URL=$(echo "${REFERENCE}" | grep -Eo '(http|https)://[a-zA-Z0-9./?=_-]*' | head -1)
			REFERENCES=$"${REFERENCES}${REFERENCE_NAME}"': '"${REFERENCE_URL}"'\n\n'
		done;
		if [[ -z "$REFERENCES" ]]; then
			for REFERENCE in $(echo ${RULE_INFO} | jq -r '.rule.htmlDesc' | sed -n '/^<h2>See<\/h2>$/,$p' | grep li); do
				REFERENCE_LI=$(echo "${REFERENCE}" | sed -n 's:.*<li>\s*\(.*\)\s*</li>.*:\1:p')
				REFERENCE_URL=$(echo "${REFERENCE_LI}" | grep -Eo '(http|https)://[a-zA-Z0-9./?=_-]*')
				REFERENCE_TEXT=$(echo "${REFERENCE_LI}" | sed -n 's!\(.*\)<a .*>\(.*\)</a>\(.*\)!\1[\2]('${REFERENCE_URL}')\3!p')
				REFERENCES=$"${REFERENCES}${REFERENCE_TEXT:-$REFERENCE_LI}"'\n\n'
			done;
		fi
		MITIGATION="n/a"
		IMPACT="n/a"
		# https://github.com/DefectDojo/sample-scan-files/blob/master/generic/generic_csv_defect_dojo.csv
		# Date | Title | CweId | Url | Severity | Description | Mitigation | Impact | References | Active | Verified | FalsePositive | Duplicate
		echo -e "\"${CREATION_DATE}\",\"${TITLE}\",\"${CWE_ID}\",\"\",\"${SEVERITY}\",\"${DESCRIPTION}\",\"${MITIGATION}\",\"${IMPACT}\",\"${REFERENCES}\",\"false\",\"false\",\"false\",\"false\""
	done
}

log "Getting data from Sonar for Defect Dojo..."

REQUEST_URI="${SONAR_API_URL}/projects/search?q=${PRODUCT_NAME_URL_ESCAPE}"
if ! JSON_BLOB=$(curl_json_get ${REQUEST_URI} -u $sonar_user:$sonar_user_password); then
	err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Unable to find the product ${project_name} in sonar" <<< "$JSON_BLOB"
fi

echo "\"date\",\"title\",\"cweid\",\"url\",\"severity\",\"description\",\"mitigation\",\"impact\",\"references\",\"active\",\"verified\",\"falsepositive\",\"duplicate\"" > $OUTFILE
for component_key in $(jq -r '.components[].key' <<< $JSON_BLOB); do
	print_open_issues $component_key >> $OUTFILE
done

DEFECT_DOJO_PRODUCT_ID=$(defect_dojo_get_or_create_product $PRODUCT_NAME_URL_ESCAPE)
if [[ -z "$DEFECT_DOJO_PRODUCT_ID" ]]; then
	err "Unable to find $project_name in Defect Dojo"
fi

DEFECT_DOJO_JIRA_PRODUCT_CONFIGURATION_ID=$(defect_dojo_get_or_create_jira_product_configuration $DEFECT_DOJO_PRODUCT_ID)
if [[ -z "$DEFECT_DOJO_JIRA_PRODUCT_CONFIGURATION_ID" ]]; then
	err "Unable to create jira configuration for $project_name in Defect Dojo"
fi

DEFECT_DOJO_ENGAGEMENT_ID=$(defect_dojo_get_or_create_engagement $DEFECT_DOJO_PRODUCT_ID)
if [[ -z "$DEFECT_DOJO_ENGAGEMENT_ID" ]]; then
	err "Unable to create engagement in Defect Dojo"
fi

if [[ ! "$(defect_dojo_import_scan_results $DEFECT_DOJO_ENGAGEMENT_ID)" == "${DEFECT_DOJO_ENGAGEMENT_ID}" ]]; then
	err "Unable to import results in Defect Dojo"
fi

log "Import completed successfully for ${project_name}. Engagement can be found on $DEFECT_DOJO_URL/engagement/$DEFECT_DOJO_ENGAGEMENT_ID"
