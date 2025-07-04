pipeline {
    agent any

    environment {
        MAVEN_HOME = tool 'maven-3.8.6'
        PATH = "${MAVEN_HOME}/bin:${PATH}"
        HELM_PATH = "C:\\Program Files\\helm\\helm.exe"
        DOCKER_IMAGE = "yahyaelkaed/petclinic:${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', 
                url: 'https://github.com/yahyaelkaed/spring-petclinic.git',
                poll: false
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package -Dcheckstyle.skip=true -Dnohttp-checkstyle.skip=true'
                sh '''
                    JAR_FILE=$(ls target/*.jar | head -1)
                    if [ -z "$JAR_FILE" ]; then
                        echo "❌ Error: No JAR file found!"
                        exit 1
                    fi
                    echo "✅ Built: $JAR_FILE"
                '''
            }
        }

        stage('Test') {
            steps {
                junit '**/target/surefire-reports/*.xml'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    withCredentials([string(credentialsId: 'sonarqube', variable: 'SONAR_TOKEN')]) {
                        sh 'mvn sonar:sonar -Dsonar.projectKey=petclinic -Dsonar.login=$SONAR_TOKEN'
                    }
                }
            }
        }

        stage('Deploy to Nexus') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'nexus-creds',
                    usernameVariable: 'NEXUS_USER',
                    passwordVariable: 'NEXUS_PASS'
                )]) {
                    sh '''
                        mvn deploy \
                          -DaltDeploymentRepository=nexus::default::http://nexus:8081/repository/maven-snapshots/ \
                          -DskipTests=true \
                          -Dcheckstyle.skip=true \
                          -Dnohttp-checkstyle.skip=true \
                          -Dusername=$NEXUS_USER \
                          -Dpassword=$NEXUS_PASS
                    '''
                }
            }
        }

        stage('Docker Build') {
            steps {
                script {
                    def jarFile = sh(script: 'ls target/spring-petclinic-*.jar | head -1', returnStdout: true).trim()
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            docker build --build-arg JAR_FILE=${jarFile} -t ${DOCKER_IMAGE} .
                            echo ${DOCKER_PASS} | docker login -u ${DOCKER_USER} --password-stdin
                            docker push ${DOCKER_IMAGE}
                        """
                    }
                }
            }
        }

        stage('Setup Kubernetes Cluster with Ansible') {
            steps {
                script {
                    sshagent(['minikube-ssh-key']) {
                        sh 'ansible-playbook -i ansible/inventory.ini ansible/setup-k8s.yml'
                    }
                }
            }
        }

        stage('Kubernetes Deploy') {
            steps {
                withCredentials([file(credentialsId: 'minikube-kubeconfig1', variable: 'KUBECONFIG_FILE')]) {
                    script {
                        sh '''
                            mkdir -p $HOME/.kube
                            cp $KUBECONFIG_FILE $HOME/.kube/config
                        '''
                        sh """
                            sed 's|image: petclinic:\${BUILD_NUMBER}|image: yahyaelkaed/petclinic:${BUILD_NUMBER}|' k8s/deployment.yaml > k8s/deployment-fixed.yaml
                            kubectl apply --validate=false -f k8s/deployment-fixed.yaml
                        """
                        sh 'kubectl apply -f k8s/service.yaml'
                        sh 'kubectl apply --validate=false -f k8s/db.yml'
                    }
                }
            }
        }

        stage('Setup Monitoring') {
            steps {
                script {
                    // 1. Create namespace without dry-run (simplest approach)
                    sh 'kubectl create namespace monitoring || true'
                    
                    // 2. Install monitoring stack with ALL metrics components disabled
                    sh '''
                        helm upgrade --install monitoring-stack prometheus-community/kube-prometheus-stack \
                            --namespace monitoring \
                            --set grafana.adminPassword=admin \
                            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
                            --set prometheus.prometheusSpec.ignoreNamespaceSelectors=true \
                            --set kubelet.serviceMonitor.enabled=false \
                            --set kube-state-metrics.enabled=false \
                            --set nodeExporter.enabled=false \
                            --set metrics-server.enabled=false \
                            --set prometheus.prometheusSpec.evaluationInterval=5m \
                            --set prometheus.prometheusSpec.scrapeInterval=5m \
                            --set prometheus.prometheusSpec.resources.requests.cpu=200m \
                            --set prometheus.prometheusSpec.resources.requests.memory=400Mi \
                            --set prometheus.prometheusSpec.resources.limits.cpu=500m \
                            --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
                            --set grafana.resources.requests.cpu=100m \
                            --set grafana.resources.requests.memory=256Mi \
                            --set alertmanager.enabled=false
                    '''
                    
                    // 3. Forcefully delete metrics-server if it exists
                    sh '''
                        kubectl delete apiservice v1beta1.metrics.k8s.io || true
                        kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
                    '''
                    
                    // 4. Verify Grafana is running (the only component we care about)
                    sh '''
                        kubectl wait --for=condition=available -n monitoring deployment/monitoring-stack-grafana --timeout=300s
                        echo "✅ Monitoring stack installed successfully!"
                        echo "Access Grafana at: http://localhost:3000 (after port-forwarding)"
                        echo "Run: kubectl port-forward -n monitoring svc/monitoring-stack-grafana 3000:80"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    sh """
                        kubectl wait --for=condition=available -n monitoring deployment/monitoring-stack-grafana --timeout=300s
                        echo "=== MONITORING ACCESS ==="
                        echo "1. Run port-forwarding:"
                        echo "kubectl port-forward -n monitoring svc/monitoring-stack-grafana 3000:80 &"
                        echo "2. Access Grafana at http://localhost:3000"
                        echo "3. Credentials: admin/admin"
                    """
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts 'target/*.jar'
            cleanWs()
        }
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs for details."
        }
    }
}
