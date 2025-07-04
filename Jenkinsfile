pipeline {
    agent any

    environment {
        MAVEN_HOME = tool 'maven-3.8.6'
        PATH = "${MAVEN_HOME}/bin:${PATH}"
        DOCKER_IMAGE = "yahyaelkaed/petclinic:${BUILD_NUMBER}"
        HELM_VERSION = "3.12.0"
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
                sshagent(['minikube-ssh-key']) {
                    sh 'ansible-playbook -i ansible/inventory.ini ansible/setup-k8s.yml'
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
                        // Replace image tag in deployment file and apply it
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
        stage('Install Helm') {
            steps {
                script {
                    // Install Helm if not present
                    sh '''
                    if ! command -v helm &> /dev/null; then
                        echo "Installing Helm ${HELM_VERSION}..."
                        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
                        chmod 700 get_helm.sh
                        ./get_helm.sh --version v${HELM_VERSION}
                    fi
                    helm version
                    '''
                }
            }
        }
        stage('Setup Guaranteed Monitoring') {
            steps {
                script {
                    // 1. Create monitoring namespace
                    sh 'kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -'
                    
                    // 2. Install foolproof monitoring stack
                    sh '''
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                    helm repo update
                    
                    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
                        --namespace monitoring \
                        --set grafana.adminPassword=admin \
                        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
                        --set prometheus.prometheusSpec.ignoreNamespaceSelectors=true \
                        --set kubelet.serviceMonitor.https=false \
                        --set prometheus.prometheusSpec.evaluationInterval=5m \
                        --set prometheus.prometheusSpec.scrapeInterval=5m \
                        --set prometheus.prometheusSpec.scrapeTimeout=30s \
                        --set prometheus.prometheusSpec.containers[0].resources.requests.memory=512Mi \
                        --set alertmanager.enabled=false \
                        --set kube-state-metrics.enabled=false \
                        --set nodeExporter.enabled=false
                    '''
                    
                    // 3. Apply minimal dashboard
                    sh 'kubectl apply -f https://raw.githubusercontent.com/grafana/grafana/main/deploy/kubernetes/grafana-dashboard-configmap.yaml -n monitoring'
                }
            }
        }
        
        stage('Access Monitoring') {
            steps {
                script {
                    // 4. Get access information
                    sh '''
                    echo "=== MONITORING ACCESS ==="
                    echo "Grafana URL: http://localhost:3000"
                    echo "Username: admin"
                    echo "Password: admin"
                    echo "=== PORT FORWARDING ==="
                    echo "Run this command on your local machine:"
                    echo "kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
                    '''
                }
            }
        }
    }
    

    post {
        always {
            archiveArtifacts 'target/*.jar'
            cleanWs()
            sh 'pkill -f "kubectl port-forward" || true'
        }
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs for details."
        }
    }
}
