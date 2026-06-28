// =============================================================================
// Job DSL — generates the Todo-List-App CI/CD pipeline job.
// Executed by the Jenkins seed job (it runs deployment-configs/jobdsl/*.groovy).
// The generated job runs the Jenkinsfile that lives in the APPLICATION repo.
// =============================================================================
folder('microservices') {
  description('Application CI/CD pipelines')
}

pipelineJob('microservices/todo-app') {
  description('Todo-List-App: Buildah image build → Gitleaks/SonarQube/Trivy → ECR → GitOps → ArgoCD')

  parameters {
    stringParam('APP_BRANCH', 'main', 'Branch of Todo-List-App to build')
  }

  // Poll SCM as a simple trigger; prefer a GitHub webhook to the Jenkins
  // endpoint (/github-webhook/) in production.
  triggers {
    scm('H/5 * * * *')
  }

  definition {
    cpsScm {
      scm {
        git {
          remote {
            url('https://github.com/pratikpagariya/Todo-List-App.git')
            credentials('github-credentials')   // Jenkins username/PAT credential id
          }
          branch('${APP_BRANCH}')
        }
      }
      scriptPath('Jenkinsfile')   // Jenkinsfile lives in the application repo
      lightweight(true)
    }
  }
}
