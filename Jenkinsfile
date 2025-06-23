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
            withCredentials([usernamePassword(credentialsId: '97555644-c9ef-4df8-80d6-26f2cc28440c', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
              writeFile file: 'settings.xml', text: """
        <settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                                      http://maven.apache.org/xsd/settings-1.0.0.xsd">
          <servers>
            <server>
              <id>nexus</id>
              <username>${NEXUS_USER}</username>
              <password>${NEXUS_PASS}</password>
            </server>
          </servers>
        </settings>
        """
              sh '''
                mvn deploy -s settings.xml -DaltDeploymentRepository=nexus::default::http://nexus:8081/repository/maven-releases/
              '''
            }
          }
        }

        stage('Docker Build & Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        docker build -t $DOCKER_IMAGE .
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                        docker push $DOCKER_IMAGE
                    """
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
