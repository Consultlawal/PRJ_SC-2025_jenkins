// Jenkinsfile

pipeline {
    agent {
        // *** IMPORTANT AGENT CHOICE ***
        // Choose ONE of these options.
        // Option 1: Docker (Highly Recommended for reproducible builds)
        // This assumes Docker is installed on your Jenkins EC2 instance.
        // It's best to build a custom Docker image containing all tools (kubectl, helm, terraform, aws-cli, istioctl).
        docker {
            image 'jenkins/jnlp-slave:latest' // A basic Jenkins agent image. You'd want a custom one.
            // Replace with your custom image if you build one with all tools
            // image 'your-custom-ci-image-with-tools:latest' // e.g., myrepo/terraform-eks-tools:latest
            args '-u 0' // Often needed for permissions in containerized Jenkins agents
        }
        // Option 2: Jenkins agent label (If you manually configured your EC2 Jenkins agent with all tools)
        // In this case, ensure your Jenkins EC2 instance has Docker, kubectl, helm, terraform, aws-cli, istioctl, Java 11
        // label 'ubuntu-latest' // If using a label, ensure the agent has all necessary tools installed globally.
    }

    environment {
        AWS_REGION         = 'us-east-1'
        CLUSTER_NAME       = 'prj-sc-2025-eks'
        REPORTS_DIR        = 'security-reports'
        
        // --- AWS Credentials Setup ---
        // Option 1 (Recommended): Rely on the EC2 Instance Profile (if Jenkins EC2 has the correct IAM role attached)
        // If your Jenkins EC2 instance has the `jenkins-ec2-profile` role from `jenkins-ec2.tf` attached,
        // AWS CLI, Terraform, etc., will automatically pick up credentials from the instance metadata.
        // In this case, you don't need AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY here or `withCredentials`.

        // Option 2 (Fallback/Specific Role): Use Jenkins Credentials Plugin
        // If your Jenkins agent is NOT on EC2 with an instance profile, or if you need to assume a DIFFERENT role.
        // Replace 'your-aws-credentials-id' with the actual ID from Jenkins Credentials.
        AWS_CREDENTIALS_ID = 'your-aws-credentials-id' // <<-- UPDATE THIS with your Jenkins credential ID

        // If you need to assume a specific role FROM these credentials, uncomment and set the ARN:
        // AWS_ASSUME_ROLE_ARN  = 'arn:aws:iam::009593259890:role/your-jenkins-deployer-role' // Example: Role for Jenkins to assume, this role needs sts:AssumeRole permissions on the instance profile's role
    }

    stages {
        // =======================================================
        // 1. SETUP & AUTHENTICATION
        // =======================================================
        stage('Setup Tools and AWS Auth') {
            steps {
                script {
                    // Ensure necessary directories exist
                    sh "mkdir -p \$HOME/.kube/"
                    sh "mkdir -p ${env.REPORTS_DIR}"

                    // --- Setup Istioctl CLI ---
                    // This block ensures istioctl is downloaded and added to PATH for the ENTIRE pipeline.
                    // If you're using a custom Docker image with Istioctl pre-installed, you can remove this.
                    sh """
                        # Only download if not already present
                        if [ ! -d "istio-1.20.0" ]; then
                            curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
                        fi
                        # Add to PATH for the current stage/step. To persist across stages, use `env.PATH` or a `withEnv` block.
                        export PATH="\$PWD/istio-1.20.0/bin:\$PATH"
                        echo "PATH updated for this step: \$PATH"
                    """
                    // To make istioctl available globally for the pipeline, a `withEnv` block would be better:
                    // withEnv(["PATH+ISTIO=${PWD}/istio-1.20.0/bin"]) {
                    //     // All steps within this block will have istioctl in PATH
                    // }
                    // For simplicity, the sh block will make it available *within that sh step*.
                    // If subsequent `sh` steps in *other* stages need `istioctl`, you'll need to re-export the PATH
                    // or use a `tool` definition/custom Docker image.
                    // For now, I'm making it available per stage that needs it.

                    // --- Verify AWS Credentials ---
                    // Use `withCredentials` block to inject AWS credentials securely.
                    // The `roleArn` parameter allows assuming a role after getting base credentials.
                    withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID, roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {
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
                    // Ensure your S3 bucket (e.g., `prj-sc-2025-tfstate`) and DynamoDB table (`prj-tf-locks2`) exist.
                    // If not, you need to create them manually or via a separate Terraform config first.
                    sh """
                        terraform init \\
                            -backend-config="bucket=${env.CLUSTER_NAME}-tfstate" \\
                            -backend-config="key=eks/terraform.tfstate" \\
                            -backend-config="region=${env.AWS_REGION}" \\
                            -backend-config="dynamodb_table=prj-tf-locks2"
                    """
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
                    echo "Example for node group: terraform import aws_eks_node_group.demo ${env.CLUSTER_NAME}:${env.CLUSTER_NAME}-node-group" // EKS node group import requires cluster_name:nodegroup_name
                    echo "--- END MANUAL INTERVENTION ---"
                }
            }
        }

        stage('Terraform Apply - Cluster & EKS OIDC') {
            steps {
                dir('terraform') {
                    // Apply only the cluster and OIDC provider first, as per previous debugging.
                    // This creates the core EKS cluster and its OIDC provider, which is critical for IRSA.
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
                            withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID, roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {
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
                    // This will include worker nodes, ALB controller IRSA, ExternalDNS IRSA, etc.
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        // =======================================================
        // 3. PREPARE KUBERNETES CONTEXT AND FETCH OUTPUTS
        // =======================================================
        stage('Update Kubeconfig and Fetch IRSA Role ARNs') {
            steps {
                script {
                    // Ensure .kube directory exists and update kubeconfig for kubectl to work.
                    // This needs AWS CLI to be authenticated (via instance profile or `withCredentials`).
                    withCredentials([aws(credentialsId: env.AWS_CREDENTIALS_ID, roleArn: env.AWS_ASSUME_ROLE_ARN ?: null)]) {
                        sh "mkdir -p \$HOME/.kube/"
                        sh "aws eks update-kubeconfig --name ${env.CLUSTER_NAME} --region ${env.AWS_REGION}"
                    }

                    dir('terraform') {
                        // Fetching Terraform outputs and making them available as Jenkins environment variables.
                        env.ALB_CONTROLLER_ARN     = sh(returnStdout: true, script: 'terraform output -raw alb_controller_role_arn').trim()
                        env.EXTERNAL_DNS_ARN       = sh(returnStdout: true, script: 'terraform output -raw external_dns_role_arn').trim()
                        env.CLUSTER_AUTOSCALER_ARN = sh(returnStdout: true, script: 'terraform output -raw autoscaler_iam_role_arn').trim()

                        echo "ALB_CONTROLLER_ARN=${env.ALB_CONTROLLER_ARN}"
                        echo "EXTERNAL_DNS_ARN=${env.EXTERNAL_DNS_ARN}"
                        echo "CLUSTER_AUTOSCALER_ARN=${env.CLUSTER_AUTOSCALER_ARN}"
                    }
                }
            }
        }
        
        // =======================================================
        // 4. APPLY EKS WORKER NODE CONFIGMAP FOR AUTHENTICATION
        // =======================================================
        stage('Apply aws-auth ConfigMap') {
            steps {
                dir('terraform') {
                    script {
                        def configMapAwsAuth = sh(returnStdout: true, script: 'terraform output -raw config_map_aws_auth')
                        sh "echo \"${configMapAwsAuth}\" | kubectl apply -f -"
                        sh "echo \"Applied aws-auth ConfigMap for worker node authentication.\""
                    }
                }
            }
        }


        // =======================================================
        // 5. SETUP NETWORKING & ACCESS (ALB and ExternalDNS)
        // =======================================================
        stage('Install AWS Load Balancer Controller') {
            steps {
                sh """
                    helm repo add aws-load-balancer-controller https://aws.github.io/eks-charts --force-update
                    helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller/aws-load-balancer-controller \\
                      --set clusterName=${env.CLUSTER_NAME} \\
                      --set serviceAccount.create=true \\
                      --set serviceAccount.name=aws-load-balancer-controller \\
                      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${env.ALB_CONTROLLER_ARN}" \\
                      --namespace kube-system --wait --atomic
                """
            }
        }

        stage('Install ExternalDNS') {
            steps {
                sh """
                    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update
                    helm upgrade --install external-dns external-dns/external-dns \\
                      --set provider=aws \\
                      --set txtOwnerId=${env.CLUSTER_NAME} \\
                      --set serviceAccount.create=true \\
                      --set serviceAccount.name=external-dns \\
                      --set policy=sync \\
                      --set aws.zoneType=public \\
                      --set registry=txt \\
                      --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${env.EXTERNAL_DNS_ARN}" \\
                      --namespace external-dns --create-namespace --wait --atomic
                """
            }
        }

        stage('Install Cluster Autoscaler') {
            when { expression { env.CLUSTER_AUTOSCALER_ARN != '' } } // Only run if the ARN is available
            steps {
                sh """
                    helm repo add autoscaler https://kubernetes.github.io/autoscaler --force-update
                    
                    helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \\
                      --namespace kube-system \\
                      --set 'autoDiscovery.clusterName'=${env.CLUSTER_NAME} \\
                      --set rbac.create=true \\
                      --set serviceAccount.create=true \\
                      --set 'serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn'="${env.CLUSTER_AUTOSCALER_ARN}" \\
                      --set awsRegion=${env.AWS_REGION} \\
                      --wait --atomic
                    
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
                    helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
                    helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --atomic
                    echo "Kyverno installation complete."
                """
            }
        }

        stage('Apply Kyverno Policies') {
            steps {
                sh """
                    if [ -d "k8s-policies/kyverno" ]; then
                        kubectl apply -f k8s-policies/kyverno/
                        sleep 10 # Give some time for policies to be processed by Kyverno
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
                    helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
                    helm upgrade --install falco falcosecurity/falco -n falco --create-namespace --wait --atomic
                    echo "Falco installation complete."
                """
            }
        }

        stage('Install Trivy Operator') {
            steps {
                sh """
                    helm repo add aqua https://aquasecurity.github.io/helm-charts --force-update
                    helm upgrade --install trivy-operator aqua/trivy-operator -n trivy-system --create-namespace --wait --atomic
                    echo "Trivy Operator installation complete."
                """
            }
        }
        
        stage('Install Istio Service Mesh') {
            steps {
                // Ensure istioctl is in PATH for this step if not globally configured
                // If using a Docker agent, ensure istioctl is in the image.
                sh """
                    # Re-add istioctl to PATH if not handled by custom Docker image or global setup
                    if [ -d "istio-1.20.0" ]; then
                        export PATH="\$PWD/istio-1.20.0/bin:\$PATH"
                    fi
                    istioctl install --set profile=demo -y
                    echo "Istio Service Mesh installed with the demo profile."
                """
            }
        }

        stage('Install Prometheus and Grafana') {
            steps {
                sh """
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update

                    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \\
                      --version 47.6.0 \\
                      --namespace monitoring --create-namespace \\
                      -f k8s-policies/monitoring/monitoring-values.yaml --atomic
                    
                    echo "Prometheus and Grafana installation complete."
                """
            }
        }

        // =======================================================
        // 7. DEPLOY APPLICATION (Hipster Shop & Route 53 Ingress)
        // =======================================================
        stage('Deploy Hipster Shop and Ingress') {
            steps {
                sh "kubectl create ns hipster-shop --dry-run=client -o yaml | kubectl apply -f -" // Creates if not exists
                sh "kubectl label namespace hipster-shop istio-injection=enabled --overwrite"
                sh "kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -n hipster-shop"
                sh "kubectl apply -f hipster-shop-ingress.yaml -n hipster-shop"
                sh "echo \"Hipster Shop and Ingress deployed. Waiting for readiness...\""
                // Increase timeout and provide more robust waiting, but keep `|| true` for non-blocking if needed
                sh "kubectl wait --for=condition=Ready pod -l app=frontend -n hipster-shop --timeout=10m || true" 
            }
        }

        // =======================================================
        // 8. RUN SECURITY AUDITS & REPORTING
        // =======================================================
        stage('Audit Calico Network Policies') {
            steps {
                sh "echo \"[+] Exporting Calico Network Policies...\""
                // Assuming Calico is installed and managing NetworkPolicies.
                // If not using Calico specifically, this will just return empty.
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
                // Wait for the job to complete
                sh "kubectl wait --for=condition=complete job/kube-bench --timeout=10m"
                script {
                    def kubeBenchPod = sh(returnStdout: true, script: "kubectl get pods -l app=kube-bench -n kube-system -o jsonpath='{.items[0].metadata.name}'").trim()
                    if (kubeBenchPod) {
                        sh "kubectl logs ${kubeBenchPod} > ${env.REPORTS_DIR}/kube-bench-report.txt"
                        sh "kubectl delete job kube-bench -n kube-system" // Clean up the job
                        echo "[+] kube-bench report saved and job cleaned up."
                    } else {
                        echo "::warning:: kube-bench pod not found. Skipping report collection and cleanup."
                    }
                }
            }
        }
        
        stage('Fetch Falco Alerts') {
            steps {
                sh "echo \"[+] Fetching Falco runtime security alerts...\""
                // Get logs from all Falco pods and consolidate
                sh "kubectl logs -l app.kubernetes.io/name=falco -n falco --all-containers --since=1h > ${env.REPORTS_DIR}/falco-alerts.log || true"
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
                // Configure this stage to run based on your needs:
                // `manualInput()`: Requires manual approval in Jenkins UI.
                // `expression { params.DESTROY_INFRASTRUCTURE == 'true' }`: Requires a build parameter.
                // `branch 'destroy'`: Only runs for a specific branch.
                // For demonstration, setting to run on success. Adjust as needed for production.
                expression { currentBuild.result == 'SUCCESS' }
            }
            steps {
                dir('terraform') {
                    // Uninstall applications and components before destroying infrastructure
                    sh "helm uninstall kube-prometheus-stack -n monitoring || true"
                    sh "helm uninstall trivy-operator -n trivy-system || true"
                    sh "helm uninstall falco -n falco || true"
                    sh "helm uninstall kyverno -n kyverno || true"
                    sh "helm uninstall cluster-autoscaler -n kube-system || true"
                    sh "helm uninstall external-dns -n external-dns || true"
                    sh "helm uninstall aws-load-balancer-controller -n kube-system || true"
                    sh "istioctl uninstall --purge -y || true" // Cleanly uninstall Istio components
                    sh "kubectl delete ns hipster-shop --ignore-not-found || true"
                    sh "kubectl delete ns external-dns --ignore-not-found || true"
                    sh "kubectl delete ns falco --ignore-not-found || true"
                    sh "kubectl delete ns kyverno --ignore-not-found || true"
                    sh "kubectl delete ns monitoring --ignore-not-found || true"
                    sh "kubectl delete ns trivy-system --ignore-not-found || true"

                    // This will show what *would* be destroyed without actually destroying.
                    echo "Performing terraform plan -destroy. Uncomment 'terraform destroy -auto-approve' to enable auto-destruction."
                    sh 'terraform plan -destroy -out=destroy.tfplan'
                    // Uncomment the line below to enable auto-destruction of your AWS resources.
                    // sh 'terraform destroy -auto-approve'
                }
            }
        }
    }
    post {
        always {
            // Cleanup workspace on the agent after the build (optional but good practice)
            cleanWs()
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