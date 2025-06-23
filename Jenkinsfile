pipeline {
    agent any

    environment {
        SONAR_SCANNER_HOME = tool 'SonarQubeScanner'
        MAVEN_HOME = tool 'maven-3.8.6'
        PATH = "${MAVEN_HOME}/bin:${PATH}"
        DOCKER_IMAGE = "yahyaelkaed/petclinic:${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/yahyaelkaed/spring-petclinic.git'
            }
        }

        stage('Build & Test') {
            steps {
                sh 'mvn clean package'
                // Enhanced verification
                script {
                    def jarFiles = findFiles(glob: '**/target/*.jar')
                    if (jarFiles.isEmpty()) {
                        error("❌ No JAR file found! Check Maven build logs.")
                    } else {
                        echo "✅ Found JAR: ${jarFiles[0].path}"
                    }
                }
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
                withCredentials([usernamePassword(credentialsId: 'nexus-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh '''
                        mvn deploy \
                         -DaltDeploymentRepository=nexus::default::http://nexus:8081/repository/maven-snapshots/ \
                          -Dusername=$NEXUS_USER \
                          -Dpassword=$NEXUS_PASS
                    '''
                }
            }
        }


        stage('Docker Build & Push') {
            steps {
                script {
                    // Verify JAR exists again before Docker build
                    def jarPath = findFiles(glob: '**/target/*.jar')[0]?.path
                    if (!jarPath) {
                        error("❌ Critical: JAR missing before Docker build!")
                    }
                    
                    withCredentials([usernamePassword(credentialsId: 'docker-hub', 
                                   usernameVariable: 'DOCKER_USER', 
                                   passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            # Build with explicit path context
                            docker build --build-arg JAR_PATH=${jarPath} -t $DOCKER_IMAGE .
                            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                            docker push $DOCKER_IMAGE
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                    sh '''
                        export KUBECONFIG=$KUBECONFIG_FILE
                        kubectl apply -f k8s/
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs for details."
        }
    }
}
