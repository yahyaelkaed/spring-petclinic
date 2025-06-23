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
                git branch: 'main', 
                url: 'https://github.com/yahyaelkaed/spring-petclinic.git',
                poll: false
            }
        }

        stage('Build & Test') {
            steps {
                sh 'mvn clean package'
                // Simple verification that works in all Jenkins environments
                sh '''
                    if [ ! -d "target" ]; then
                        echo "❌ Error: target directory not found!"
                        exit 1
                    fi
                    if [ ! -f target/*.jar ]; then
                        echo "❌ Error: No JAR file found in target directory!"
                        exit 1
                    fi
                    echo "✅ JAR file exists in target directory"
                    ls -la target/
                '''
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
                withCredentials([usernamePassword(credentialsId: 'nexus-creds', 
                               usernameVariable: 'NEXUS_USER', 
                               passwordVariable: 'NEXUS_PASS')]) {
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
                    // Get the exact JAR filename using shell
                    def jarFile = sh(script: 'ls target/*.jar | head -1', returnStdout: true).trim()
                    if (!jarFile) {
                        error("❌ Critical: No JAR file found in target directory!")
                    }
                    echo "✅ Found JAR file: ${jarFile}"
                    
                    // Build Docker image with the found JAR file
                    withCredentials([usernamePassword(credentialsId: 'docker-hub', 
                                   usernameVariable: 'DOCKER_USER', 
                                   passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            docker build --build-arg JAR_FILE=${jarFile} -t ${DOCKER_IMAGE} .
                            echo ${DOCKER_PASS} | docker login -u ${DOCKER_USER} --password-stdin
                            docker push ${DOCKER_IMAGE}
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                    sh '''
                        export KUBECONFIG=${KUBECONFIG_FILE}
                        kubectl apply -f k8s/
                    '''
                }
            }
        }
    }

    post {
        always {
            junit '**/target/surefire-reports/*.xml'
            archiveArtifacts '**/target/*.jar'
        }
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs for details."
        }
    }
}
