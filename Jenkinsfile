pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli
    command: ["cat"]
    tty: true
  - name: kubectl
    image: bitnami/kubectl:latest
    command: ["cat"]
    tty: true
    securityContext:
      runAsUser: 0
    env:
    - name: KUBECONFIG
      value: /kube/config
    volumeMounts:
    - name: kubeconfig-secret
      mountPath: /kube/config
      subPath: kubeconfig
  - name: dind
    image: docker:dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
    args: 
    - "--storage-driver=overlay2"
    volumeMounts:
    - name: docker-config
      mountPath: /etc/docker/daemon.json
      subPath: daemon.json
    - name: workspace-volume
      mountPath: /home/jenkins/agent
  - name: jnlp
    image: jenkins/inbound-agent:3309.v27b_9314fd1a_4-1
    env:
    - name: JENKINS_AGENT_WORKDIR
      value: "/home/jenkins/agent"
    volumeMounts:
    - mountPath: "/home/jenkins/agent"
      name: workspace-volume
  volumes:
  - name: workspace-volume
    emptyDir: {}
  - name: docker-config
    configMap:
      name: docker-daemon-config
  - name: kubeconfig-secret
    secret:
      secretName: kubeconfig-secret
'''
        }
    }

    environment {
        // -------------------------------------------------------------------------
        // CRITICAL FIX: Set this to JUST the domain name.
        // Docker cannot handle 'http://' or '/repository/' in the registry variable.
        // The path 'my-repository' is handled by REPO_NAME below.
        // -------------------------------------------------------------------------
        NEXUS_REGISTRY = 'nexus.imcc.com'
        
        REPO_NAME = 'my-repository'
        IMAGE_NAME = 'client'
    }

    stages {
        stage('CHECK') {
            steps {
                echo "DEBUG >>> NEW JENKINSFILE IS ACTIVE"
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
                        
                        docker build -t client:latest .
                        docker image ls
                    '''
                }
            }
        }

        stage('SonarQube Scan') {
            steps {
                container('sonar-scanner') {
                    withCredentials([string(credentialsId: '2401200_solutionbox', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            sonar-scanner \
                              -Dsonar.projectKey=2401200_solutionbox \
                              -Dsonar.host.url=http://my-sonarqube-sonarqube.sonarqube.svc.cluster.local:9000 \
                              -Dsonar.login=$SONAR_TOKEN
                        '''
                    }
                }
            }
        }

        stage('Login to Nexus Registry') {
            steps {
                container('dind') {
                    sh """
                        docker --version
                        sleep 5
                        # Log in to the Nexus domain
                        docker login ${NEXUS_REGISTRY} -u admin -p Changeme@2025
                    """
                }
            }
        }

        stage('Tag + Push Images') {
            steps {
                container('dind') {
                    sh """
                        # Tag logic: nexus.imcc.com/my-repository/client:10
                        docker tag client:latest ${NEXUS_REGISTRY}/${REPO_NAME}/${IMAGE_NAME}:${BUILD_NUMBER}
                        docker tag client:latest ${NEXUS_REGISTRY}/${REPO_NAME}/${IMAGE_NAME}:latest

                        # Push BOTH the specific version and latest
                        docker push ${NEXUS_REGISTRY}/${REPO_NAME}/${IMAGE_NAME}:${BUILD_NUMBER}
                        docker push ${NEXUS_REGISTRY}/${REPO_NAME}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('Create Namespace') {
            steps {
                container('kubectl') {
                    sh """
                        # 1. Create namespace if it doesn't exist
                        kubectl get namespace 2401200 || kubectl create namespace 2401200

                        # 2. Create Docker Registry Secret using the PUBLIC URL
                        kubectl create secret docker-registry nexus-secret \
                          --docker-server=${NEXUS_REGISTRY} \
                          --docker-username=admin \
                          --docker-password=Changeme@2025 \
                          --namespace=2401200 \
                          --dry-run=client -o yaml | kubectl apply -f -
                    """
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    // Ensure the folder matches exactly (Capital 'K')
                    dir('K8s-deployment') { 
                        sh """
                            echo "DEBUG: Verifying deployment.yaml..."
                            ls -la deployment.yaml

                            # Update deployment.yaml to use the full public Nexus URL
                            sed -i "s|client:latest|${NEXUS_REGISTRY}/${REPO_NAME}/${IMAGE_NAME}:${BUILD_NUMBER}|g" deployment.yaml
                            
                            kubectl apply -f deployment.yaml
                            
                            # Give it a moment to start
                            sleep 5
                            kubectl get pods -n 2401200
                        """
                    }
                }
            }
        }
    }
}