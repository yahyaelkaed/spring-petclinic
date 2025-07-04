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
        stage('Enable Metrics Server') {
            steps {
                script {
                    // Enable and wait for metrics-server
                    sh '''
                    minikube addons enable metrics-server
                    kubectl wait --namespace kube-system \
                      --for=condition=ready pod \
                      --selector=k8s-app=metrics-server \
                      --timeout=300s
                    '''
                }
            }
        }

        stage('Setup Monitoring Stack') {
            steps {
                script {
                    // 1. Create namespace and add Helm repo
                    sh '''
                    kubectl apply -f monitoring/namespace.yaml
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                    helm repo update
                    '''

                    // 2. Install monitoring stack with persistent storage
                    sh """
                    helm upgrade --install monitoring-stack prometheus-community/kube-prometheus-stack \
                        --namespace monitoring \
                        --set grafana.adminPassword='admin' \
                        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
                        --set grafana.sidecar.dashboards.enabled=true \
                        --set grafana.sidecar.dashboards.label=grafana_dashboard \
                        --set alertmanager.enabled=true \
                        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName="standard" \
                        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]="ReadWriteOnce" \
                        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="10Gi"
                    """

                    // 3. Apply additional configs
                    sh '''
                    kubectl apply -f monitoring/grafana-dashboards.yaml
                    kubectl apply -f monitoring/jenkins-service-monitor.yaml
                    '''
                }
            }
        }

        stage('Verify Monitoring') {
            steps {
                script {
                    // 1. Verify components
                    sh '''
                    kubectl wait --for=condition=ready -n monitoring pod -l app.kubernetes.io/instance=monitoring-stack --timeout=300s
                    '''

                    // 2. Get access details
                    sh '''
                    echo "=== MONITORING ACCESS ==="
                    echo "Grafana:     http://localhost:3000"
                    echo "Username:    admin"
                    echo "Password:    $(kubectl get secret -n monitoring monitoring-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"
                    echo "Prometheus:  http://localhost:9090"
                    echo "Alertmanager: http://localhost:9093"
                    '''

                    // 3. Temporary port-forward (for testing)
                    sh 'kubectl port-forward -n monitoring svc/monitoring-stack-grafana 3000:80 &'
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
