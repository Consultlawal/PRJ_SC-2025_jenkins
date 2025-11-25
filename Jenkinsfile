// Jenkinsfile

pipeline {
    agent {
        // Option 1: Use a specific Docker image (recommended for consistent environments)
        // docker { 
        //     image 'your-custom-ci-image-with-tools:latest' // e.g., myrepo/terraform-eks-tools:latest
        //     args '-u 0' // Often needed for permissions in containerized Jenkins agents
        // }
        // Option 2: Use a Jenkins agent label (if you have specific agents configured with tools)
        label 'ubuntu-latest' // Replace with your actual Jenkins agent label if different
    }

    environment {
        AWS_REGION        = 'us-east-1'
        CLUSTER_NAME      = 'prj-sc-2025-eks'
        REPORTS_DIR       = 'security-reports'

        // --- AWS Credentials Setup ---
        // Use Jenkins Credentials Plugin to securely store your AWS Access Key ID and Secret Access Key.
        // Replace 'your-aws-credentials-id' with the ID you assign in Jenkins.
        // If your Jenkins agent runs on EC2/EKS with an IAM Instance Profile/Service Account,
        // you might not need to explicitly set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY here.
        // If so, you can remove the `withCredentials` block and rely on the instance profile/SA.
        AWS_ACCESS_KEY_ID     = credentials('your-aws-credentials-id').AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY = credentials('your-aws-credentials-id').AWS_SECRET_ACCESS_KEY
        
        // If you need to assume a specific role FROM these credentials, uncomment and set the ARN:
        // AWS_ASSUME_ROLE_ARN   = 'arn:aws:iam::009593259890:role/your-jenkins-deployer-role' // Example: Role for Jenkins to assume
    }

    stages {
        // =======================================================
        // 1. SETUP & AUTHENTICATION
        // =======================================================
        stage('Setup Tools and AWS Auth') {
            steps {
                script {
                    // Ensure necessary directories exist
                    sh "mkdir -p $HOME/.kube/"
                    sh "mkdir -p ${env.REPORTS_DIR}"

                    // --- Setup Istioctl CLI ---
                    // This downloads and adds istioctl to PATH for the current shell session.
                    sh """
                        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
                        export PATH="\$PWD/istio-1.20.0/bin:\$PATH"
                        # Make istioctl available to subsequent shell steps in this Jenkins build
                        # Note: This makes it available per-step. If you use a 'tool' definition or custom image, this might not be needed.
                        echo "Adding istioctl to PATH for current build steps: \$PWD/istio-1.20.0/bin"
                        # For cross-step path persistence in Jenkins, you might use 'addToPath' or a shared library
                        // Not strictly necessary if istioctl is installed globally on the agent or in your Docker image
                    """

                    // --- Verify AWS Credentials ---
                    // This block ensures the AWS CLI is configured and can authenticate.
                    // It will either use instance profile, or the explicit AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY.
                    withCredentials([aws(credentialsId: 'your-aws-credentials-id', roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) { // Pass roleArn if defined
                        sh 'aws sts get-caller-identity' // Verify AWS credentials are working
                    }
                }
            }
        }

        // =======================================================
        // 2. PROVISION INFRASTRUCTURE (EKS, VPC, IRSA Roles)
        // =======================================================
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    // Initialize Terraform with the S3 backend and DynamoDB locking.
                    sh 'terraform init'
                }
            }
        }
        
        stage('Terraform State Cleanup & Import (Manual Intervention Needed)') {
            steps {
                script {
                    echo "--- MANUAL INTERVENTION / ONE-TIME STEPS ---"
                    echo "If you encounter 'EntityAlreadyExists' errors for existing resources like 'aws_eks_node_group.demo' or 'aws_iam_role.demo_cluster',"
                    echo "you will need to run 'terraform state rm' and/or 'terraform import' commands manually from the 'terraform' directory on your Jenkins agent."
                    echo "These are NOT typically part of an automated pipeline due to their one-time nature."
                    echo "Example for role: terraform import aws_iam_role.demo_cluster arn:aws:iam::009593259890:role/terraform-eks-demo-cluster"
                    echo "Example for node group: terraform import aws_eks_node_group.demo prj-sc-2025-eks:prj-sc-2025-eks-node-group" // EKS node group import requires cluster_name:nodegroup_name
                    echo "--- END MANUAL INTERVENTION ---"
                }
            }
        }


        stage('Terraform Apply - Cluster & EKS OIDC') {
            steps {
                dir('terraform') {
                    // Apply only the cluster and OIDC provider first, as per previous debugging.
                    sh "terraform apply -target=aws_eks_cluster.demo -target=aws_iam_openid_connect_provider.demo -auto-approve"
                }
            }
        }

        stage('Wait for EKS OIDC Provider') {
            steps {
                dir('terraform') {
                    script {
                        def oidcIssuerUrl = sh(returnStdout: true, script: 'terraform output -raw eks_oidc_issuer_url').trim()
                        def oidcProviderArn = sh(returnStdout: true, script: 'terraform output -raw eks_oidc_provider_arn').trim()

                        if (!oidcIssuerUrl || !oidcProviderArn) {
                            error "Error: Terraform did not output EKS OIDC Issuer URL or Provider ARN. OIDC provider might not have been created."
                        }

                        echo "EKS OIDC Issuer URL from Terraform: ${oidcIssuerUrl}"
                        echo "EKS OIDC Provider ARN from Terraform: ${oidcProviderArn}"

                        echo "Waiting for OIDC Identity Provider to become active in IAM using ARN..."
                        def maxAttempts = 30 // 30 iterations * 15 seconds = 7.5 minutes max wait
                        def checkOutput = ""
                        for (int i = 1; i <= maxAttempts; i++) {
                            // Using the `withCredentials` block here ensures AWS CLI uses the correct permissions
                            withCredentials([aws(credentialsId: 'your-aws-credentials-id', roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {
                                checkOutput = sh(returnStdout: true, script: "aws iam get-open-id-connect-provider --open-id-connect-provider-arn \"${oidcProviderArn}\" --query \"Url\" --output text 2>/dev/null").trim()
                            }
                            if (checkOutput) {
                                echo "OIDC Identity Provider found in IAM and URL is '${checkOutput}'."
                                echo "OIDC provider is active and fully propagated."
                                break
                            } else {
                                echo "OIDC Identity Provider not yet found/active in IAM or API call failed. Waiting... (${i}/${maxAttempts})"
                            }
                            sleep 15
                        }

                        if (!checkOutput) {
                            error "Error: OIDC Identity Provider did not become active in IAM within the expected time (${oidcProviderArn})."
                        }
                    }
                }
            }
        }

        stage('Terraform Apply - Remaining Resources') {
            steps {
                dir('terraform') {
                    // Apply all remaining resources defined in your Terraform configuration.
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        // =======================================================
        // 3. FETCH TERRAFORM OUTPUTS
        // =======================================================
        stage('Fetch IRSA Role ARNs') {
            steps {
                dir('terraform') {
                    script {
                        // Fetching Terraform outputs and making them available as Jenkins environment variables.
                        env.ALB_CONTROLLER_ARN    = sh(returnStdout: true, script: 'terraform output -raw alb_controller_role_arn').trim()
                        env.EXTERNAL_DNS_ARN      = sh(returnStdout: true, script: 'terraform output -raw external_dns_role_arn').trim()
                        env.CLUSTER_AUTOSCALER_ARN = sh(returnStdout: true, script: 'terraform output -raw autoscaler_iam_role_arn').trim()

                        echo "ALB_CONTROLLER_ARN=${env.ALB_CONTROLLER_ARN}"
                        echo "EXTERNAL_DNS_ARN=${env.EXTERNAL_DNS_ARN}"
                        echo "CLUSTER_AUTOSCALER_ARN=${env.CLUSTER_AUTOSCALER_ARN}"
                    }
                }
            }
        }

        // =======================================================
        // 4. PREPARE KUBERNETES CONTEXT
        // =======================================================
        stage('Update Kubeconfig') {
            steps {
                // Ensure .kube directory exists and update kubeconfig for kubectl to work.
                sh "mkdir -p \$HOME/.kube/"
                sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION}"
            }
        }

        // =======================================================
        // 5. SETUP NETWORKING & ACCESS (ALB and ExternalDNS)
        // =======================================================
        stage('Install AWS Load Balancer Controller') {
            steps {
                sh """
                    helm repo add aws-load-balancer-controller https://aws.github.io/eks-charts
                    helm repo update

                    helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller/aws-load-balancer-controller \\
                      --set clusterName=${env.CLUSTER_NAME} \\
                      --set serviceAccount.create=true \\
                      --set serviceAccount.name=aws-load-balancer-controller \\
                      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${env.ALB_CONTROLLER_ARN}" \\
                      --namespace kube-system --wait
                """
            }
        }

        stage('Install ExternalDNS') {
            steps {
                sh """
                    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
                    helm repo update

                    helm upgrade --install external-dns external-dns/external-dns \\
                      --set provider=aws \\
                      --set txtOwnerId=${env.CLUSTER_NAME} \\
                      --set serviceAccount.create=true \\
                      --set serviceAccount.name=external-dns \\
                      --set policy=sync \\
                      --set aws.zoneType=public \\
                      --set registry=txt \\
                      --set serviceAccount.annotations."eks\\.amazonaws\.com/role-arn"="${env.EXTERNAL_DNS_ARN}" \\
                      --namespace external-dns --create-namespace --wait
                """
            }
        }

        stage('Install Cluster Autoscaler') {
            when { expression { env.CLUSTER_AUTOSCALER_ARN != '' } } // Only run if the ARN is available
            steps {
                sh """
                    helm repo add autoscaler https://kubernetes.github.io/autoscaler
                    helm repo update
                    
                    helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \\
                      --namespace kube-system \\
                      --set 'autoDiscovery.clusterName'=${env.CLUSTER_NAME} \\
                      --set rbac.create=true \\
                      --set serviceAccount.create=true \\
                      --set 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn'="${env.CLUSTER_AUTOSCALER_ARN}" \\
                      --set awsRegion=${env.AWS_REGION} \\
                      --wait
                    
                    echo "Cluster Autoscaler installation complete."
                """
            }
        }

        // =======================================================
        // 6. DEPLOY SECURITY MESH COMPONENTS
        // =======================================================
        stage('Install Kyverno') {
            steps {
                sh """
                    helm repo add kyverno https://kyverno.github.io/kyverno/
                    helm repo update
                    helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
                    echo "Kyverno installation complete."
                """
            }
        }

        stage('Apply Kyverno Policies') {
            steps {
                sh """
                    if [ -d "k8s-policies/kyverno" ]; then
                        kubectl apply -f k8s-policies/kyverno/
                        sleep 10
                        echo "Kyverno policies applied from k8s-policies/kyverno/"
                    else
                        echo "::warning:: k8s-policies/kyverno/ directory not found. Skipping Kyverno policy application."
                    fi
                """
            }
        }

        stage('Install Falco') {
            steps {
                sh """
                    helm repo add falcosecurity https://falcosecurity.github.io/charts
                    helm repo update
                    helm upgrade --install falco falcosecurity/falco -n falco --create-namespace --wait
                    echo "Falco installation complete."
                """
            }
        }

        stage('Install Trivy Operator') {
            steps {
                sh """
                    helm repo add aqua https://aquasecurity.github.io/helm-charts
                    helm repo update
                    helm upgrade --install trivy-operator aqua/trivy-operator -n trivy-system --create-namespace --wait
                    echo "Trivy Operator installation complete."
                """
            }
        }
        
        stage('Install Istio Service Mesh') {
            steps {
                sh "istioctl install --set profile=demo -y"
                sh "echo \"Istio Service Mesh installed with the demo profile.\""
            }
        }

        stage('Install Prometheus and Grafana') {
            steps {
                sh """
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                    helm repo update

                    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \\
                      --version 47.6.0 \\
                      --namespace monitoring --create-namespace \\
                      -f k8s-policies/monitoring/monitoring-values.yaml
                    
                    echo "Prometheus and Grafana installation complete."
                """
            }
        }

        // =======================================================
        // 7. DEPLOY APPLICATION (Hipster Shop & Route 53 Ingress)
        // =======================================================
        stage('Deploy Hipster Shop and Ingress') {
            steps {
                sh "kubectl create ns hipster-shop || true"
                sh "kubectl label namespace hipster-shop istio-injection=enabled --overwrite"
                sh "kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -n hipster-shop"
                sh "kubectl apply -f hipster-shop-ingress.yaml -n hipster-shop"
                sh "echo \"Hipster Shop and Ingress deployed. Waiting for readiness...\""
                sh "kubectl wait --for=condition=Ready pod -l app=frontend -n hipster-shop --timeout=5m || true"
            }
        }

        // =======================================================
        // 8. RUN SECURITY AUDITS & REPORTING
        // =======================================================
        stage('Audit Calico Network Policies') {
            steps {
                sh "echo \"[+] Exporting Calico Network Policies...\""
                sh "kubectl get networkpolicies -A -o json > ${env.REPORTS_DIR}/calico-networkpolicies.json || true"
            }
        }
        
        stage('Audit Istio Security Configurations') {
            steps {
                sh "echo \"[+] Exporting Istio Security Configurations...\""
                sh "kubectl get peerauthentication -A -o json > ${env.REPORTS_DIR}/istio-peerauth.json || true"
                sh "kubectl get authorizationpolicy -A -o json > ${env.REPORTS_DIR}/istio-authz.json || true"
            }
        }
        
        stage('Run kube-bench (CIS Benchmark)') {
            steps {
                sh "echo \"[+] Running kube-bench CIS Benchmark scan inside the cluster...\""
                sh "kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml"
                sh "kubectl wait --for=condition=complete job/kube-bench --timeout=10m"
                script {
                    def kubeBenchPod = sh(returnStdout: true, script: "kubectl get pods -l app=kube-bench -o jsonpath='{.items[0].metadata.name}'").trim()
                    sh "kubectl logs ${kubeBenchPod} > ${env.REPORTS_DIR}/kube-bench-report.txt"
                }
                sh "kubectl delete -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml"
                sh "echo \"[+] kube-bench report saved.\""
            }
        }
        
        stage('Fetch Falco Alerts') {
            steps {
                sh "echo \"[+] Fetching Falco runtime security alerts...\""
                sh "kubectl logs -l app.kubernetes.io/name=falco -n falco --tail=1000 > ${env.REPORTS_DIR}/falco-alerts.log || true"
                sh "echo \"[+] Falco alerts exported.\""
            }
        }

        stage('Check Trivy Operator Vulnerability Reports') {
            steps {
                sh "echo \"[+] Checking Trivy Operator vulnerability reports...\""
                sh "kubectl get vulnerabilityreports -A -o yaml > ${env.REPORTS_DIR}/trivy-operator-vulnerabilityreports.yaml || true"
                sh "kubectl get configauditreports -A -o yaml > ${env.REPORTS_DIR}/trivy-operator-configauditreports.yaml || true"
                sh "echo \"[+] Trivy Operator reports exported.\""
            }
        }

        stage('Check Kyverno Policy Reports') {
            steps {
                sh "echo \"[+] Checking Kyverno policy reports...\""
                sh "kubectl get policyreports -A -o yaml > ${env.REPORTS_DIR}/kyverno-policyreports.yaml || true"
                sh "echo \"[+] Kyverno policy reports exported.\""
            }
        }

        // =======================================================
        // 9. ARCHIVE REPORTS
        // =======================================================
        stage('Archive Security Reports') {
            steps {
                // Archives all files in the security-reports directory as build artifacts.
                archiveArtifacts artifacts: "${env.REPORTS_DIR}/**", fingerprint: true, allowEmptyArchive: true
            }
        }

        // =======================================================
        // 10. CLEANUP (Terraform Destroy - Optional)
        // =======================================================
        stage('Terraform Destroy (Optional)') {
            when {
                // This stage can be configured to run always, on failure, or based on a parameter.
                // For a typical development pipeline, you might not want auto-destroy.
                // For a full CI/CD, you might make this a manual step or conditional based on branch/environment.
                // Example: expression { params.DESTROY_INFRASTRUCTURE == true }
                // For now, it's set to run on success, but you should adjust.
                expression { currentBuild.result == 'SUCCESS' } // Adjust this condition as needed
            }
            steps {
                dir('terraform') {
                    sh "istioctl uninstall --purge -y || true" // Cleanly uninstall Istio components
                    echo "Performing terraform plan -destroy. Uncomment 'terraform destroy -auto-approve' to enable auto-destruction."
                    // Uncomment the line below (and remove the 'terraform plan -destroy') to enable auto-destruction of your AWS resources.
                    // sh 'terraform destroy -auto-approve'
                    sh 'terraform plan -destroy' // This will show what *would* be destroyed without actually destroying.
                }
            }
        }
    }
    post {
        always {
            // Cleanup workspace on the agent after the build (optional)
            // cleanWs() 
        }
        success {
            echo 'Deployment Pipeline finished successfully!'
        }
        failure {
            echo 'Deployment Pipeline failed!'
            // Add notification logic here (e.g., email, Slack)
        }
    }
}