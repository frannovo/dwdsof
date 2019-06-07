# Dealing with DevSecOps Findings

This repository contains all the stuff used for [Dealing with DevSEcOps findinings](https://open-security-summit.org/tracks/devsecops/working-sessions/dealing-with-security-findings/) session in [OWASP Open Securiry Summit](https://open-security-summit.org)


# WARNING
Please don't use this set up in production and let us know of any problems by logging an issue.

# Prerequisites
- Installed packages:
  - docker-ce: 18.09.5
  - docker-compose version 1.24.0

- User with uid 1000 in the host environment belongs to docker group
- Atlassian account to get trial licences for Jira Core and Jira Software

# Installation
```
git clone https://github.com/frannovo/dwdsof.git
cd dwdsof/
git clone https://github.com/teamatldocker/jira.git jira
git clone https://github.com/DefectDojo/django-DefectDojo
mkdir data/postgresql_data
mkdir data/jira_postgresqldata 
chmod 0777 -R data
docker-compose up -d
```

# Post Installation
- Configure Jira
1. Get a trial Jira License from your Atlassian account
2. Configure Jira Webhook - [Defect Dojo Jira Intergration](https://defectdojo.readthedocs.io/en/latest/features.html#jira-integration)

- Configure Jenkins
1. - Create link to jenkins home
   ```
   # ln -s /path/to/dwdsof/data/jenkins_data /var/jenkins_home
   ```

2. Get admin credentials
   ```
   docker exec -t $(docker ps | grep jenkins | awk '{print $1}') cat /var/jenkins_home/secrets/initialAdminPassword
   ```
3. Copy JobTemplate and scripts
   ```
   cp -r /path/to/dwdsof/jenkins/JobTemplate /path/to/dwdsof/data/jenkins_data/jobs
   cp -r /path/to/dwdsof/jenkins/scripts /path/to/dwdsof/data/jenkins_data/
   ```
4. Reload Jenkins (Manage Jenkins > Reload Configuration from disk)
5. Create credentials
   1. devops-credentials: username and password to login into Jira, Sonar, and DefectDojo
   2. devops-dd-token: secret string (Defect dojo API Token) 
   3. zap-api-token: secert string 


## DefectDojo tweek
  
  This change has been made to automatically create jira issues when a new finding is populated in the DefectDojo engagement when importing a scan.
   ```
   --- a/dojo/api_v2/serializers.py
   +++ b/dojo/api_v2/serializers.py
   @@ -17,7 +17,7 @@ import datetime
    import six
    from django.utils.translation import ugettext_lazy as _
    import json
   -
   +from dojo.tasks import add_issue_task, update_issue_task
    
    class TagList(list):
        def __init__(self, *args, **kwargs):
   @@ -616,6 +616,8 @@ class ImportScanSerializer(TaggitSerializer,    serializers.Serializer):
    
                        item.endpoints.add(ep)
    
   +                # Automatic push to jira (WIP)
   +                add_issue_task.delay(item, True)
                    # if item.unsaved_tags is not None:
                    #    item.tags = item.unsaved_tags  
   ```

# Authors
* [Juan Pedro Escalona](https://github.com/jpescalona)
* [Rafael Jimenez](https://github.com/rjimgal)
* [Fran Novo](https://github.com/frannovo)
* [Claudio Camerino](https://github.com/clazba)


# Limitations
- Concurrent builds
  - In this set up concurrent bulds will fail due to container name colission
  

# Troubleshooting
- SonarQube can't start: 
1. Check data folder permissions
   ```
   chmod 0777 -R data
   ```
2. Elasticsearch exception:
   ```
   rm -rf /path/to/dwdsof-oss2019/data/sonarqube/es6
   ```

