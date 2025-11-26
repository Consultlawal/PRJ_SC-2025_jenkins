// Jenkinsfile

pipeline {
    agent {
        // Option 1: Docker agent (recommended)
        docker {
            image 'jenkins/jnlp-slave:latest'
            args '-u 0'
        }

        // Option 2: Standard Jenkins agent (uncomment if needed)
        // label 'ubuntu-latest'
    }

    environment {
        AWS_REGION         = 'us-east-1'
        CLUSTER_NAME       = 'prj-sc-2025-eks'
        REPORTS_DIR        = 'security-reports'

        // Jenkins Credentials ID (update with your ID)
        AWS_CREDENTIALS_ID = 'your-aws-credentials-id'

        // Optional: Role to assume
        // AWS_ASSUME_ROLE_ARN = 'arn:aws:iam::009593259890:role/your-jenkins-deployer-role'
    }

    stages {

        /* ============================================
         * 1. SETUP & AUTHENTICATION
         * ============================================ */
        stage('Setup Tools and AWS Auth') {
            steps {
                script {
                    sh "mkdir -p \$HOME/.kube"
                    sh "mkdir -p ${env.REPORTS_DIR}"

                    // Download Istioctl if missing
                    sh """
                        if [ ! -d "istio-1.20.0" ]; then
                            curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
                        fi
                        export PATH="\$PWD/istio-1.20.0/bin:\$PATH"
                    """

                    withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID, 
                        roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {
                        sh "aws sts get-caller-identity"
                    }
                }
            }
        }

        /* ============================================
         * 2. TERRAFORM INIT
         * ============================================ */
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh """
                        terraform init \
                          -backend-config="bucket=${env.CLUSTER_NAME}-tfstate" \
                          -backend-config="key=eks/terraform.tfstate" \
                          -backend-config="region=${env.AWS_REGION}" \
                          -backend-config="dynamodb_table=prj-tf-locks2"
                    """
                }
            }
        }

        stage('Terraform State Cleanup & Import (Manual)') {
            steps {
                echo """
                    --- MANUAL TERRAFORM STATE FIX ---
                    If you get EntityAlreadyExists errors:
                    
                    terraform state rm aws_iam_role.demo_cluster
                    terraform import aws_iam_role.demo_cluster <role-arn>

                    terraform state rm aws_eks_node_group.demo
                    terraform import aws_eks_node_group.demo <cluster:nodegroup>
                    -----------------------------------------------
                """
            }
        }

        stage('Terraform Apply - Core Cluster & OIDC') {
            steps {
                dir('terraform') {
                    sh """
                        terraform apply \
                          -target=aws_eks_cluster.demo \
                          -target=aws_iam_openid_connect_provider.demo \
                          -auto-approve
                    """
                }
            }
        }

        stage('Wait for EKS OIDC Provider') {
            steps {
                dir('terraform') {
                    script {
                        def oidcUrl = sh(returnStdout: true, script: 'terraform output -raw eks_oidc_issuer_url').trim()
                        def oidcArn = sh(returnStdout: true, script: 'terraform output -raw eks_oidc_provider_arn').trim()

                        if (!oidcUrl || !oidcArn) {
                            error "OIDC output missing."
                        }

                        echo "OIDC Provider ARN: ${oidcArn}"

                        def check = ""
                        for (int i = 1; i <= 30; i++) {
                            withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID,
                                roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {

                                check = sh(
                                  returnStdout: true,
                                  script: "aws iam get-open-id-connect-provider --open-id-connect-provider-arn '${oidcArn}' --query Url --output text 2>/dev/null"
                                ).trim()
                            }

                            if (check) {
                                echo "OIDC Provider Active."
                                break
                            }

                            echo "Waiting for OIDC provider... (${i}/30)"
                            sleep 15
                        }

                        if (!check) error "OIDC still not active after timeout."
                    }
                }
            }
        }

        stage('Terraform Apply - Remaining Resources') {
            steps {
                dir('terraform') {
                    sh "terraform apply -auto-approve"
                }
            }
        }

        /* ============================================
         * 3. KUBECONFIG + OUTPUTS
         * ============================================ */
        stage('Update Kubeconfig & Fetch IRSA ARNs') {
            steps {
                script {
                    withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID,
                        roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {

                        sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION}"
                    }

                    dir('terraform') {
                        env.ALB_CONTROLLER_ARN =
                            sh(returnStdout: true, script: 'terraform output -raw alb_controller_role_arn').trim()

                        env.EXTERNAL_DNS_ARN =
                            sh(returnStdout: true, script: 'terraform output -raw external_dns_role_arn').trim()

                        env.CLUSTER_AUTOSCALER_ARN =
                            sh(returnStdout: true, script: 'terraform output -raw autoscaler_iam_role_arn').trim()
                    }
                }
            }
        }

        /* ============================================
         * 4. APPLY aws-auth CONFIGMAP
         * ============================================ */
        stage('Apply aws-auth ConfigMap') {
            steps {
                dir('terraform') {
                    script {
                        def config = sh(returnStdout: true, script: 'terraform output -raw config_map_aws_auth')
                        sh "echo '${config}' | kubectl apply -f -"
                    }
                }
            }
        }

        /* ============================================
         * 5. INSTALL NETWORKING (ALB, DNS)
         * ============================================ */
        stage('Install AWS Load Balancer Controller') {
            steps {
                sh """
                    helm repo add aws-load-balancer-controller https://aws.github.io/eks-charts --force-update
                    helm upgrade --install aws-load-balancer-controller \
                      aws-load-balancer-controller/aws-load-balancer-controller \
                      --set clusterName=${env.CLUSTER_NAME} \
                      --set serviceAccount.create=true \
                      --set serviceAccount.name=aws-load-balancer-controller \
                      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${env.ALB_CONTROLLER_ARN}" \
                      -n kube-system --wait --atomic
                """
            }
        }

        stage('Install ExternalDNS') {
            steps {
                sh """
                    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update
                    helm upgrade --install external-dns external-dns/external-dns \
                      --set provider=aws \
                      --set txtOwnerId=${env.CLUSTER_NAME} \
                      --set serviceAccount.create=true \
                      --set serviceAccount.name=external-dns \
                      --set policy=sync \
                      --set aws.zoneType=public \
                      --set registry=txt \
                      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${env.EXTERNAL_DNS_ARN}" \
                      -n external-dns --create-namespace --wait --atomic
                """
            }
        }

        /* ============================================
         * 6. SECURITY: Kyverno, Falco, Trivy, Istio, Monitoring
         * ============================================ */
        stage('Install Kyverno') {
            steps {
                sh """
                    helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
                    helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --atomic
                """
            }
        }

        stage('Apply Kyverno Policies') {
            steps {
                sh """
                    if [ -d "k8s-policies/kyverno" ]; then
                        kubectl apply -f k8s-policies/kyverno/
                        sleep 10
                    else
                        echo "Kyverno policies directory not found."
                    fi
                """
            }
        }

        stage('Install Falco') {
            steps {
                sh """
                    helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
                    helm upgrade --install falco falcosecurity/falco \
                      -n falco --create-namespace --wait --atomic
                """
            }
        }

        stage('Install Trivy Operator') {
            steps {
                sh """
                    helm repo add aqua https://aquasecurity.github.io/helm-charts --force-update
                    helm upgrade --install trivy-operator aqua/trivy-operator \
                      -n trivy-system --create-namespace --wait --atomic
                """
            }
        }

        stage('Install Istio') {
            steps {
                sh """
                    if [ -d "istio-1.20.0" ]; then
                        export PATH="\$PWD/istio-1.20.0/bin:\$PATH"
                    fi
                    istioctl install --set profile=demo -y
                """
            }
        }

        stage('Install Prometheus & Grafana') {
            steps {
                sh """
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
                    helm upgrade --install kube-prometheus-stack \
                      prometheus-community/kube-prometheus-stack \
                      --version 47.6.0 \
                      -n monitoring --create-namespace \
                      -f k8s-policies/monitoring/monitoring-values.yaml --atomic
                """
            }
        }

        /* ============================================
         * 7. DEPLOY APPLICATION
         * ============================================ */
        stage('Deploy Hipster Shop') {
            steps {
                sh """
                    kubectl create ns hipster-shop --dry-run=client -o yaml | kubectl apply -f -
                    kubectl label ns hipster-shop istio-injection=enabled --overwrite
                    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -n hipster-shop
                    kubectl apply -f hipster-shop-ingress.yaml -n hipster-shop
                    kubectl wait --for=condition=Ready pod -l app=frontend -n hipster-shop --timeout=10m || true
                """
            }
        }

        /* ============================================
         * 8. SECURITY REPORTING
         * ============================================ */
        stage('Export Calico Policies') {
            steps {
                sh "kubectl get networkpolicies -A -o json > ${env.REPORTS_DIR}/calico-networkpolicies.json || true"
            }
        }

        stage('Export Istio Security Configs') {
            steps {
                sh """
                    kubectl get peerauthentication -A -o json > ${env.REPORTS_DIR}/istio-peerauth.json || true
                    kubectl get authorizationpolicy -A -o json > ${env.REPORTS_DIR}/istio-authz.json || true
                """
            }
        }

        stage('Run kube-bench') {
            steps {
                sh "kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml"
                sh "kubectl wait --for=condition=complete job/kube-bench --timeout=10m"

                script {
                    def pod = sh(
                      returnStdout: true,
                      script: "kubectl get pods -l app=kube-bench -n kube-system -o jsonpath='{.items[0].metadata.name}'"
                    ).trim()

                    if (pod) {
                        sh "kubectl logs ${pod} > ${env.REPORTS_DIR}/kube-bench-report.txt"
                        sh "kubectl delete job kube-bench -n kube-system"
                    }
                }
            }
        }

        stage('Fetch Falco Alerts') {
            steps {
                sh "kubectl logs -l app.kubernetes.io/name=falco -n falco --all-containers --since=1h > ${env.REPORTS_DIR}/falco-alerts.log || true"
            }
        }

        stage('Export Trivy Reports') {
            steps {
                sh """
                    kubectl get vulnerabilityreports -A -o yaml > ${env.REPORTS_DIR}/trivy-vuln.yaml || true
                    kubectl get configauditreports -A -o yaml > ${env.REPORTS_DIR}/trivy-config.yaml || true
                """
            }
        }

        stage('Export Kyverno Reports') {
            steps {
                sh "kubectl get policyreports -A -o yaml > ${env.REPORTS_DIR}/kyverno-policyreports.yaml || true"
            }
        }

        /* ============================================
         * 9. ARCHIVE REPORTS
         * ============================================ */
        stage('Archive Reports') {
            steps {
                archiveArtifacts artifacts: "${env.REPORTS_DIR}/**", fingerprint: true, allowEmptyArchive: true
            }
        }

        /* ============================================
         * 10. CLEANUP / DESTROY (OPTIONAL)
         * ============================================ */
        stage('Terraform Destroy (Optional)') {
            when { expression { currentBuild.result == 'SUCCESS' } }
            steps {
                dir('terraform') {
                    sh "helm uninstall kube-prometheus-stack -n monitoring || true"
                    sh "helm uninstall trivy-operator -n trivy-system || true"
                    sh "helm uninstall falco -n falco || true"
                    sh "helm uninstall kyverno -n kyverno || true"
                    sh "helm uninstall cluster-autoscaler -n kube-system || true"
                    sh "helm uninstall external-dns -n external-dns || true"
                    sh "helm uninstall aws-load-balancer-controller -n kube-system || true"
                    sh "istioctl uninstall --purge -y || true"

                    sh "kubectl delete ns hipster-shop --ignore-not-found || true"

                    sh "terraform plan -destroy -out=destroy.tfplan"
                    // sh "terraform destroy -auto-approve"
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}
