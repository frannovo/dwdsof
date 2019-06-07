#!/bin/bash -x

source ${JENKINS_HOME}/scripts/common.sh

ensure_vars project_name \
	user \
	password \
	defect_dojo_api_key

DEFECT_DOJO_TEST_TYPE=${DEFECT_DOJO_TEST_TYPE-"ZAP Scan"}
ZAP_FILE=${ZAP_FILE-"zap-report.xml"}
OUTFILE="${ZAP_FILE}"

log "ZAP for Defect Dojo..."

DEFECT_DOJO_PRODUCT_ID=$(defect_dojo_get_or_create_product $PRODUCT_NAME_URL_ESCAPE)
if [[ -z "$DEFECT_DOJO_PRODUCT_ID" ]]; then
	err "Unable to find $project_name in Defect Dojo"
fi

DEFECT_DOJO_ENGAGEMENT_ID=$(defect_dojo_get_or_create_engagement $DEFECT_DOJO_PRODUCT_ID)
if [[ -z "$DEFECT_DOJO_ENGAGEMENT_ID" ]]; then
	err "Unable to create engagement in Defect Dojo"
fi


if [[ ! "$(defect_dojo_import_scan_results $DEFECT_DOJO_ENGAGEMENT_ID)" == "${DEFECT_DOJO_ENGAGEMENT_ID}" ]]; then
	err "Unable to import results in Defect Dojo"
fi

log "Import completed successfully for ${project_name}. Engagement can be found on $DEFECT_DOJO_URL/engagement/$DEFECT_DOJO_ENGAGEMENT_ID"
