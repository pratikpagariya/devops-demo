// =============================================================================
// Job DSL — folders, views, and the seed job itself.
// Executed by the JCasC "seed-job" (and by Jenkinsfile.seed).
// =============================================================================

folder('platform') {
  description('Platform / shared pipelines')
}

folder('microservices') {
  description('Per-microservice CI pipelines')
}

// Re-runnable seed pipeline that regenerates jobs from this repo.
pipelineJob('platform/seed-job') {
  description('Regenerates all pipeline jobs from deployment-configs/jobdsl')
  definition {
    cpsScm {
      scm {
        git {
          remote { url('https://github.com/your-org/devops-demo.git') }
          branch('main')
        }
      }
      scriptPath('deployment-configs/jenkins/Jenkinsfile.seed')
    }
  }
}

listView('microservices/all') {
  jobs { regex('microservices/.*') }
  columns {
    status()
    weather()
    name()
    lastSuccess()
    lastFailure()
    buildButton()
  }
}
