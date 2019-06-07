#!/usr/bin/env bash

source ${JENKINS_HOME}/scripts/functions.sh

PRODUCT_NAME_URL_ESCAPE="${project_name// /%20}"
SONAR_API_URL=${SONAR_API_URL-"http://$SONAR_URL/api"}
DEFECT_DOJO_URL=${DEFECT_DOJO_URL-"http://defect-dojo.domain.com"}
DEFECT_DOJO_API_URL=${DEFECT_DOJO_API_URL-"$DEFECT_DOJO_URL/api/v2"}
# PRODUCT
DEFECT_DOJO_PRODUCT_TYPE=${DEFECT_DOJO_PRODUCT_TYPE-"Uncategorized"}
# ENGAGEMENT
DEFECT_DOJO_ENGAGEMENT_NAME=${DEFECT_DOJO_ENGAGEMENT_NAME-"CI/CD Automated Security Testing"}
DEFECT_DOJO_ENGAGEMENT_TYPE=${DEFECT_DOJO_ENGAGEMENT_TYPE-"CI/CD"}
# TEST
DEFECT_DOJO_SCAN_TYPE=${DEFECT_DOJO_SCAN_TYPE-"Generic Findings Import"}
DEFECT_DOJO_ENVIRONMENT=${bamboo_environment-"Development"}

# Common
DEFECT_DOJO_LEAD_ID=${DEFECT_DOJO_LEAD_ID-1}

defect_dojo_get_or_create_entity() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/${2}/"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI?name=${1}&limit=100" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	fi
	ID=$(jq -r ".results[] | select(.name==\"${1}\") | .id" <<< "${JSON_BLOB}")
	if [[ -z $ID ]]; then
		DATA=$(jq -n \
			--arg name "${1}" \
			'{
				"name": $name
			}')
		if ! JSON_BLOB=$(curl_json_post "$REQUEST_URI" -H "Authorization: Token $defect_dojo_api_key" -d "${DATA}"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
		echo $(jq -r '.id' <<< "${JSON_BLOB}")
	else
		echo $ID
	fi
}

defect_dojo_get_or_create_test_type() {
	defect_dojo_get_or_create_entity "${1}" "test_types"
}

defect_dojo_get_or_create_environment() {
	defect_dojo_get_or_create_entity "${1}" "development_environments"
}

defect_dojo_get_or_create_product_type() {
	defect_dojo_get_or_create_entity "${1}" "product_types"
}

defect_dojo_get_or_create_product() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/products/"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI?name=${1}&limit=100" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	fi
	if [[ -z $(jq -r ".results[] | select(.name==\"${project_name}\") | .id" <<< "${JSON_BLOB}") ]]; then
		prod_type=$(defect_dojo_get_or_create_product_type $DEFECT_DOJO_PRODUCT_TYPE)
		DATA=$(jq -n \
			--arg name "${project_name}" \
			--arg platform "web" \
			--arg origin "internal" \
			--arg lifecycle "construction" \
			--arg prod_type $prod_type \
			--arg description "${project_name} has been automatically imported from CD/CI pipelines" \
			'{
			  "name": $name,
			  "platform": $platform,
			  "origin": $origin,
			  "lifecycle": $lifecycle,
			  "prod_type": $prod_type,
			  "description": $description
			}'
		)
		if ! JSON_BLOB=$(curl_json_post "$REQUEST_URI" -H "Authorization: Token $defect_dojo_api_key" -d "${DATA}"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
		echo $(jq -r '.id' <<< "${JSON_BLOB}")
	else
	    echo $(jq -r ".results[] | select(.name==\"${project_name}\") | .id" <<< "${JSON_BLOB}")
	fi
}

defect_dojo_get_or_create_jira_product_configuration() {
	product_id=$1
	REQUEST_URI="$DEFECT_DOJO_API_URL/jira_product_configurations/"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI?product=${product_id}&limit=100" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	fi
	if [[ -z $(jq -r ".results[] | select(.product==${product_id}) | .id" <<< "${JSON_BLOB}") ]]; then
		REQUEST_URI="$DEFECT_DOJO_API_URL/jira_product_configurations/"
		DATA=$(jq -n \
			--arg product "${product_id}" \
			--arg push_all_issues true \
			--arg enable_engagement_epic_mapping true \
			--arg project_key "${project_key}" \
			--arg push_notes true \
			--arg conf ${jira_id} \
			'{
				"product": $product, 
				"push_all_issues": $push_all_issues, 
				"enable_engagement_epic_mapping": $enable_engagement_epic_mapping, 
				"project_key": $project_key,
				"push_notes": $push_notes,
				"conf": $conf
			}'
		)
		if ! JSON_BLOB=$(curl_json_post "$REQUEST_URI" -H "Authorization: Token $defect_dojo_api_key" -d "${DATA}"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
		echo $(jq -r '.id' <<< "${JSON_BLOB}")
	else
	    echo $(jq -r ".results[] | select(.product==${product_id}) | .id" <<< "${JSON_BLOB}")
	fi
}

defect_dojo_get_current_id_engagement() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/engagements/?product="${1}"&active=true"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	else
	  echo $(jq '.results[] | select(.engagement_type=="CI/CD") | .id' <<< $JSON_BLOB)
	fi
}

defect_dojo_deactivate_engagement() {
	CURRENT_ENGAGEMENT=$(defect_dojo_get_current_id_engagement "${1}")
	if [ $CURRENT_ENGAGEMENT ]; then
		log "Found engagement $CURRENT_ENGAGEMENT. It will be closed."
		REQUEST_URI="$DEFECT_DOJO_API_URL/engagements/$CURRENT_ENGAGEMENT/close"
		if ! JSON_BLOB=$(curl_json_post "$REQUEST_URI" -H "Authorization: Token $defect_dojo_api_key"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
	fi
}

defect_dojo_get_or_create_engagement() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/engagements/"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI?product=${1}&active=true" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	fi
	if [[ -z $(jq -r ".results[] | select(.name==\"${DEFECT_DOJO_ENGAGEMENT_NAME}\") | .id" <<< "${JSON_BLOB}") ]]; then
		DATA=$(jq -n \
			--arg product_id "${1}" \
			--arg engagement_name "${DEFECT_DOJO_ENGAGEMENT_NAME}" \
			--arg target_start "$(date +%Y-%m-%d)" \
			--arg target_end "$(date --date='next month' +%Y-%m-%d)" \
			--arg engagement_type "${DEFECT_DOJO_ENGAGEMENT_TYPE}" \
			--arg lead_id ${DEFECT_DOJO_LEAD_ID} \
			--arg build_id "${ci_buildNumber}" \
			--arg version "${ci_version}" \
			--arg source_uri "${git_repositoryUrl}" \
			--arg commit_hash "${git_revision}" \
			--arg branch_tag "${git_branch}" \
			'{
			  "product": $product_id,
			  "name": $engagement_name,
			  "description": "Engagement to collect results from automated tests",
			  "target_start": $target_start,
			  "target_end": $target_end,
			  "engagement_type": $engagement_type,
			  "lead": $lead_id,
				"status": "In Progress",
				"build_id": $build_id,
				"version": $version,
				"source_code_management_uri": $source_uri,
				"commit_hash": $commit_hash,
				"branch_tag": $branch_tag
			}'
		)
		if ! JSON_BLOB=$(curl_json_post "${REQUEST_URI}" -H "Authorization: Token $defect_dojo_api_key" -d "${DATA}"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
		echo $(jq -r '.id' <<< "${JSON_BLOB}")
	else
		echo $(jq -r ".results[] | select(.name==\"${DEFECT_DOJO_ENGAGEMENT_NAME}\") | .id" <<< "${JSON_BLOB}")
	fi
}

defect_dojo_import_scan_results() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/import-scan/"
	if [[ ${DEFECT_DOJO_TEST_TYPE} == *"Sonar"* ]]; then
        if ! JSON_BLOB=$(curl -X POST -s -H "Authorization: Token $defect_dojo_api_key" \
         --form "file=@$OUTFILE" \
				 --form "scan_type=${DEFECT_DOJO_SCAN_TYPE}" \
         --form "test_type=${DEFECT_DOJO_TEST_TYPE}" \
         --form "engagement=${1}" --form "verified=true" --form "scan_date=$(date +%Y-%m-%d)" --form "close_old_findings=true" "$REQUEST_URI"); then
            err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
        fi
	else
	    if ! JSON_BLOB=$(curl -X POST -s -H "Authorization: Token $defect_dojo_api_key" \
         --form "file=@$OUTFILE" --form "scan_type=${DEFECT_DOJO_TEST_TYPE}" \
         --form "engagement=${1}" --form "verified=true" --form "scan_date=$(date +%Y-%m-%d)" --form "close_old_findings=true" "$REQUEST_URI"); then
            err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
        fi
	fi
	jq  -r '.engagement' <<< "$JSON_BLOB"
}

defect_dojo_get_or_create_jira_configuration() {
  REQUEST_URI="$DEFECT_DOJO_API_URL/jira_configurations/"
	if ! JSON_BLOB=$(curl_json_get "$REQUEST_URI?url=${JIRA_URL}" -H "Authorization: Token $defect_dojo_api_key"); then
		err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
	fi
	if [[ -z $(jq -r ".results[] | select(.url==\"${JIRA_URL}\") | .id" <<< "${JSON_BLOB}") ]]; then
		DATA=$(jq -n \
			--arg username "${user}" \
			--arg password "${password}" \
			--arg default_issue_type "task" \
			--arg critical_mapping_severity: "Highest" \
			--arg high_mapping_severity: "High" \
			--arg low_mapping_severity: "Lowest" \
			--arg url: "http://jira.env.local:8080" \
			--arg medium_mapping_severity: "Low" \
			--arg close_status_key: 10001 \
			--arg open_status_key: 10000 \
			--arg epic_name_id: 0 \
			--arg finding_text: "Test DD jira integration",
			'{
			"username": $username,
			"password": $password,
			"default_issue_type": $default_issue_type,
			"critical_mapping_severity": $critical_mapping_severity,
			"high_mapping_severity": $high_mapping_severity,
			"low_mapping_severity": $low_mapping_severity,
			"url": $url,
			"medium_mapping_severity": $medium_mapping_severity,
			"close_status_key": $close_status_key,
			"open_status_key": $open_status_key,
			"epic_name_id": $epic_name_id
			}'
		)
		if ! JSON_BLOB=$(curl_json_post "${REQUEST_URI}" -H "Authorization: Token $defect_dojo_api_key" -d "${DATA}"); then
			err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
		fi
		echo $(jq -r '.id' <<< "${JSON_BLOB}")
	else
		echo $(jq -r ".results[] | select(.name==\"${DEFECT_DOJO_ENGAGEMENT_NAME}\") | .id" <<< "${JSON_BLOB}")
	fi
}

defect_dojo_import_scan_results() {
	REQUEST_URI="$DEFECT_DOJO_API_URL/import-scan/"
	if [[ ${DEFECT_DOJO_TEST_TYPE} == *"Sonar"* ]]; then
        if ! JSON_BLOB=$(curl -X POST -s -H "Authorization: Token $defect_dojo_api_key" \
         --form "file=@$OUTFILE" \
				 --form "scan_type=${DEFECT_DOJO_SCAN_TYPE}" \
         --form "test_type=${DEFECT_DOJO_TEST_TYPE}" \
         --form "engagement=${1}" --form "verified=true" --form "scan_date=$(date +%Y-%m-%d)" --form "close_old_findings=true" "$REQUEST_URI"); then
            err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
        fi
	else
	    if ! JSON_BLOB=$(curl -X POST -s -H "Authorization: Token $defect_dojo_api_key" \
         --form "file=@$OUTFILE" --form "scan_type=${DEFECT_DOJO_TEST_TYPE}" \
         --form "engagement=${1}" --form "verified=true" --form "scan_date=$(date +%Y-%m-%d)" --form "close_old_findings=true" "$REQUEST_URI"); then
            err "REQUEST ERROR: Curl returned $? calling ${REQUEST_URI}." "Defect Dojo returned the following response:" <<< "$JSON_BLOB"
        fi
	fi
	jq  -r '.engagement' <<< "$JSON_BLOB"
}