pipeline {
    agent any

    stages {
        stage('Initialize Terraform') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Apply Terraform') {
            steps {
                sh 'terraform apply -auto-approve'
            }
        }

        stage('Wait for Deployment') {
            steps {
                sleep 30
            }
        }

        stage('Run Ansible Playbook') {
            steps {
                sh 'ansible-playbook -i /root/terraform/inventory.ini install_kubernetes.yaml'
            }
        }
    }
}
