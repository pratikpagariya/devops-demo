// =============================================================================
// Job DSL — generate one CI pipeline per microservice.
// Keep this list aligned with ecr_repository_names / params/dev.tfvars.
// Each job runs the shared deployment-configs/jenkins/Jenkinsfile.
// =============================================================================

def services = [
  'api-gateway',
  'user-service',
  'order-service',
  'notification-service',
  'payment-service',
  'analytics-service',
]

services.each { svc ->
  pipelineJob("microservices/${svc}") {
    description("CI pipeline for ${svc}")

    parameters {
      stringParam('GIT_BRANCH', 'main', 'Branch to build')
    }

    triggers {
      // Poll SCM as a fallback; prefer a webhook to the Jenkins endpoint.
      scm('H/5 * * * *')
    }

    definition {
      cpsScm {
        scm {
          git {
            remote {
              url("https://github.com/your-org/${svc}.git")
              credentials('git-credentials')   // imported from Secrets Manager
            }
            branch('${GIT_BRANCH}')
          }
        }
        scriptPath('Jenkinsfile')   // each service repo ships its own Jenkinsfile
      }
    }
  }
}
