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

    // --- NEW: Dedicated Node.js container for frontend build/test
    - name: node
        image: node:18-alpine // Using a lightweight, recent Node image
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

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 90, unit: 'MINUTES')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(returnStdout: true,
                        script: 'git rev-parse --short=7 HEAD').trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        stage('Install & Test - Server') {
            steps {
                dir('server') {
                    container('dind') {
                        sh '''
                            apk add --no-cache nodejs npm || true
                            npm ci
                            npm test -- --silent || true
                        '''
                    }
                }
            }
        }
    
        // --- INSERTED NEW FRONTEND TEST/COVERAGE STAGE ---
        stage('Frontend Test and Report Generation') {
            steps {
                container('node') {
                    sh '''
                        echo "Installing dependencies..."
                        npm ci

                        echo "Running Jest tests and generating LCOV/JUnit reports..."
                        # This command runs tests, enables coverage, and outputs the JUnit XML file.
                        # Ensure 'jest-junit' is installed in your package.json dependencies.
                        npm test -- --coverage --testResultsProcessor=jest-junit --ci

                        echo "Reports generated: coverage/lcov.info and test-results.xml."
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                container('dind') {
                    sh '''
                        echo "Waiting for Docker daemon..."
                        for i in $(seq 1 30); do
                          docker info >/dev/null 2>&1 && break
                          echo "dockerd not ready ($i)..."
                          sleep 2
                        done

                        docker build -t solutionbox:latest .
                        docker image ls
                    '''
                }
            }
        }
    
        stage('Build - Tag - Push Images') {
            steps {
                container('dind') {
                    script {
                        // Build client image from repo root (you have only frontend)
                        sh "docker build -t ${CLIENT_REPO}:${IMAGE_TAG} -f Dockerfile . || true"
                        sh "docker tag ${CLIENT_REPO}:${IMAGE_TAG} ${CLIENT_REPO}:latest || true"

                        // Try push only if Docker credentials exist; otherwise skip
                        try {
                            withCredentials([usernamePassword(credentialsId: env.DOCKER_CREDENTIALS_ID,
                                usernameVariable: 'DOCKER_USER',
                                passwordVariable: 'DOCKER_PASS')]) {
                                sh '''
                                    echo "$DOCKER_PASS" | docker login ${REGISTRY} -u "$DOCKER_USER" --password-stdin
                                    docker push ${CLIENT_REPO}:${IMAGE_TAG} || true
                                    docker push ${CLIENT_REPO}:latest || true
                                '''
                            }
                        } catch (err) {
                            echo "Docker push skipped: credentials not found or login failed. Image built locally in DIND pod."
                        }

                        sh 'docker image ls | grep ${IMAGE_TAG} || true'
                    }
                }
            }
        }

        // --- UPDATED SONARQUBE ANALYSIS STAGE ---
        stage('SonarQube Analysis') {
            steps {
                container('sonar-scanner') {
                    withCredentials([string(credentialsId: env.SONAR_CREDENTIALS_ID, variable: 'SONAR_TOKEN')]) {
                        sh '''
                            echo "Testing Sonar reachability..."
                            curl -sS --max-time 5 [http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000/](http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000/) || true

                            # SonarQube Scanner for a React/JS project
                            sonar-scanner \\
                              -Dsonar.projectKey=stack-overflow-client \\
                              -Dsonar.host.url=[http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000](http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000) \\
                              -Dsonar.login=${SONAR_TOKEN} \\
                              \\
                              # --- JAVASCRIPT/TYPESCRIPT PROPERTIES FOR COVERAGE ---
                              -Dsonar.sources=./src \\
                              -Dsonar.tests=./src \\
                              # Coverage report path (LCOV format is standard for JS)
                              -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \\
                              # Test execution report path (JUnit XML format)
                              -Dsonar.testExecutionReportPaths=test-results.xml
                              # --- END JAVASCRIPT/TYPESCRIPT PROPERTIES ---
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
