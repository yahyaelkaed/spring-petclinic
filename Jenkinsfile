pipeline {
    agent any

    environment {
        MAVEN_HOME = tool 'maven-3.8.6'
        PATH = "${MAVEN_HOME}/bin:${PATH}"
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
        stage('Setup Monitoring Stack') {
            steps {
                script {
                    // Deploy monitoring stack using Helm or kubectl
                    sh 'kubectl apply -f monitoring/namespace.yaml'
                    sh 'helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring'
                    
                    // Alternatively, you can use kubectl with your own manifests
                    // sh 'kubectl apply -f monitoring/prometheus/'
                    // sh 'kubectl apply -f monitoring/grafana/'
                    // sh 'kubectl apply -f monitoring/alertmanager/'
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
