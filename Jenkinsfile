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

        stage('Kubernetes Deploy') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        // Method 1: Using withKubeConfig (recommended)
                        withKubeConfig([credentialsId: 'kubeconfig']) {
                            sh '''
                                kubectl version --client
                                kubectl apply -f k8s/
                            '''
                        }

                        // Method 2: Fallback manual installation (uncomment if needed)
                        /*
                        if (!isUnix()) {
                            error("Windows agents not supported for Kubernetes deployment")
                        }
                        
                        sh '''
                            # Install kubectl if missing
                            if ! command -v kubectl >/dev/null 2>&1; then
                                echo "Installing kubectl..."
                                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                                chmod +x kubectl
                                mkdir -p "$HOME/bin"
                                mv kubectl "$HOME/bin/"
                                export PATH="$PATH:$HOME/bin"
                            fi
                            
                            export KUBECONFIG=${KUBECONFIG}
                            kubectl apply -f k8s/
                        '''
                        */
                    }
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
