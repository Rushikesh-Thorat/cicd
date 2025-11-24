pipeline {
  agent {
    kubernetes {
      yaml """
apiVersion: v1
kind: Pod
spec:
  securityContext:
    fsGroup: 1000
  containers:
  - name: dind
    image: docker:24-dind
    securityContext:
      privileged: true
    env:
      - name: DOCKER_TLS_CERTDIR
        value: ""
    volumeMounts:
      - name: docker-graph-storage
        mountPath: /var/lib/docker
  - name: docker-cli
    image: docker:24-cli
    command:
      - cat
    tty: true
    volumeMounts:
      - name: docker-graph-storage
        mountPath: /var/lib/docker
  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli:latest
    command:
      - cat
    tty: true
  - name: kubectl
    image: bitnami/kubectl:latest
    command:
      - cat
    tty: true
    env:
      - name: KUBECONFIG
        value: /kube/config
    volumeMounts:
      - name: kubeconfig-secret
        mountPath: /kube/config
        subPath: kubeconfig
  volumes:
    - name: docker-graph-storage
      emptyDir: {}
    - name: kubeconfig-secret
      secret:
        secretName: kubeconfig-secret
"""
    }
  }

  environment {
    // Registry and repo settings - change to your registry if needed
    REGISTRY = "docker.io"
    SERVER_REPO = "yourdockerhubusername/stack-overflow-server"
    CLIENT_REPO = "yourdockerhubusername/stack-overflow-client"

    // Jenkins credential IDs
    DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'   // username/password or token
    SONAR_CREDENTIALS_ID = '2401200'                  // secret text for Sonar token
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 90, unit: 'MINUTES')
    timestamps()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
        }
      }
    }

    stage('Install & Test - Server') {
      steps {
        dir('server') {
          container('docker-cli') {
            sh '''
              echo "Installing server deps..."
              apk add --no-cache nodejs npm >/dev/null 2>&1 || true
              npm ci
              echo "Running server tests..."
              npm test -- --silent || true
            '''
          }
        }
      }
    }

   
stage('Build Docker Image') {
  steps {
    container('dind') {
      sh '''
        echo "Waiting for Docker daemon to be ready..."
        for i in $(seq 1 30); do
          docker info >/dev/null 2>&1 && break
          echo "dockerd not ready yet ($i) ... waiting"
          sleep 2
        done

        echo "Building Docker image for project..."
        docker build -t solutionbox:latest .

        echo "Docker images available in this job:"
        docker image ls
      '''
    }
  }
}


    stage('Build - Tag - Push Images') {
      steps {
        container('docker-cli') {
          script {
            // Build server image
            sh "docker build -t ${SERVER_REPO}:${IMAGE_TAG} -f server/Dockerfile server"
            sh "docker tag ${SERVER_REPO}:${IMAGE_TAG} ${SERVER_REPO}:latest"

            // Build client image (served by nginx in production Dockerfile)
            sh "docker build -t ${CLIENT_REPO}:${IMAGE_TAG} -f client/Dockerfile client"
            sh "docker tag ${CLIENT_REPO}:${IMAGE_TAG} ${CLIENT_REPO}:latest"

            // Push both images
            sh "docker push ${SERVER_REPO}:${IMAGE_TAG}"
            sh "docker push ${SERVER_REPO}:latest || true"

            sh "docker push ${CLIENT_REPO}:${IMAGE_TAG}"
            sh "docker push ${CLIENT_REPO}:latest || true"

            sh 'docker image ls | grep ${IMAGE_TAG} || true'
          }
        }
      }
    }

    stage('SonarQube Analysis') {
      steps {
        container('sonar-scanner') {
          withCredentials([string(credentialsId: env.SONAR_CREDENTIALS_ID, variable: 'SONAR_TOKEN')]) {
            sh '''
              sonar-scanner \
                -Dsonar.projectKey=2401200_solutionbox \
                -Dsonar.host.url=http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000 \
                -Dsonar.login=${SONAR_TOKEN} \
                -Dsonar.sources=server,client/src || true
            '''
          }
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        container('kubectl') {
          dir('k8s-deployment') {
            sh '''
              # Update deployments to the new images and apply manifests
              kubectl set image deployment/stack-overflow-server stack-overflow-server=${SERVER_REPO}:${IMAGE_TAG} -n stack-overflow || true
              kubectl set image deployment/stack-overflow-client stack-overflow-client=${CLIENT_REPO}:${IMAGE_TAG} -n stack-overflow || true

              kubectl apply -f .

              # Wait for rollouts
              kubectl rollout status deployment/stack-overflow-server -n stack-overflow --timeout=120s || true
              kubectl rollout status deployment/stack-overflow-client -n stack-overflow --timeout=120s || true
            '''
          }
        }
      }
    }
  }

  post {
    success {
      echo "Pipeline succeeded. Pushed images: ${SERVER_REPO}:${IMAGE_TAG}, ${CLIENT_REPO}:${IMAGE_TAG}"
    }
    failure {
      echo "Pipeline failed. See console logs for errors."
    }
    always {
      container('docker-cli') {
        sh 'docker image prune -f || true'
      }
    }
  }
}