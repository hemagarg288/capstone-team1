pipeline {
    agent any

        stage('Run Ansible Playbook to install kubernetes') {
            steps {
                sh 'ansible-playbook -i /root/terraform/inventory.ini install_kubernetes.yaml'
            }
        }

        stage('Run Ansible Playbook to install Docker Compose Helm and argoCD') {
            steps {
                sh 'ansible-playbook -i /root/terraform/inventory.ini install_dc_helm_argocd.yaml'
            }
        }
    }
}
