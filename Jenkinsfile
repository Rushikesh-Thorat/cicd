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

  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli:latest
    command: ["cat"]
    tty: true

  - name: kubectl
    image: bitnami/kubectl:latest
    command: ["cat"]
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

  stages {
        stage('Build Docker Image') {
            steps {
                container('dind') {
                    sh '''
                        sleep 15
                        docker build -t sbox:latest .
                        docker image ls
                    '''
                }
            }
        }

        stage('Run Tests in Docker') {
            steps {
                container('dind') {
                    sh '''
                        docker run --rm sbox:latest \
                        pytest --maxfail=1 --disable-warnings --cov=. --cov-report=xml
                    '''
                }
            }
        }
        stage('Frontend Test and Report Generation') {
    steps {
        // IMPORTANT: Replace 'sonar-scanner' with your Node.js container image.
        // If your 'sonar-scanner' container is large enough to include Node/npm, you can keep it,
        // but typically a dedicated 'node' container is best for frontend steps.
        container('node') { // Suggesting 'node' container, update this if needed
            sh '''
                echo "Installing dependencies..."
                # Use 'npm install' or 'yarn install'
                npm install

                echo "Running Jest tests and generating LCOV/JUnit reports..."
                # 1. Run tests with coverage enabled.
                # Jest outputs reports to './coverage' and 'test-results.xml' by default.
                # Ensure your Jest configuration file (jest.config.js or package.json) has:
                # - coverageReporters: ["lcov", "text"]
                # - testResultsProcessor: "jest-junit" (if you want the JUnit report)
                npm test -- --coverage --outputFile=test-results.xml --ci

                # Note: We are using 'npm test' which assumes your package.json has a 'test' script.
                
                echo "Reports generated: coverage/lcov.info and test-results.xml."
            '''
        }
    }
}

// --- UPDATED SONARQUBE ANALYSIS STAGE ---
stage('SonarQube Analysis') {
    steps {
        container('sonar-scanner') {
            withCredentials([string(credentialsId: 'sonar-token-2401200', variable: 'SONAR_TOKEN')]) {
                sh '''
                    # SonarQube Scanner for a React/JS project
                    sonar-scanner \
                        -Dsonar.projectKey=24011200-Solution-Box \
                        -Dsonar.host.url=[http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000](http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000) \
                        -Dsonar.login=$SONAR_TOKEN \
                        \
                        # --- START JAVASCRIPT/TYPESCRIPT PROPERTIES ---
                        # Coverage report path (LCOV format is standard for JS)
                        -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
                        \
                        # Test execution report path (JUnit XML format)
                        -Dsonar.testExecutionReportPaths=test-results.xml
                        # --- END JAVASCRIPT/TYPESCRIPT PROPERTIES ---
                '''
            }
        }
    }
}

        stage('Login to Docker Registry') {
            steps {
                container('dind') {
                    sh 'docker --version'
                    sh 'sleep 10'
                    sh 'docker login nexus-service-for-docker-hosted-registry.nexus.svc.cluster.local:8085 -u admin -p Changeme@2025'
                }
            }
        }
        stage('Build - Tag - Push') {
            steps {
                container('dind') {
                    sh 'docker tag sbox:latest nexus-service-for-docker-hosted-registry.nexus.svc.cluster.local:8085/ajinkya-project/sbox:v1'
                    sh 'docker push nexus-service-for-docker-hosted-registry.nexus.svc.cluster.local:8085/rushi-project/sbox:v1'
                    sh 'docker pull nexus-service-for-docker-hosted-registry.nexus.svc.cluster.local:8085/rushi-project/sbox:v1'
                    sh 'docker image ls'
                }
            }
        }

    stage('Deploy to Kubernetes') {
      steps {
        container('kubectl') {
          dir('k8s-deployment') {
            sh '''
              kubectl set image deployment/stack-overflow-client \
                stack-overflow-client=${CLIENT_REPO}:${IMAGE_TAG} -n stack-overflow || true

              kubectl apply -f .

              kubectl rollout status deployment/stack-overflow-client \
                -n stack-overflow --timeout=120s || true
            '''
          }
        }
      }
    }
  }

  post {
    success { echo "Pipeline Succeeded!" }
    failure { echo "Pipeline Failed" }
    always {
      container('dind') {
        sh 'docker image prune -f || true'
      }
    }
  }
}

