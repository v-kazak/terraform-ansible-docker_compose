.PHONY: start ansible terraform destroy
start:
	terraform -chdir=terraform init
	terraform -chdir=terraform fmt
	terraform -chdir=terraform validate
	terraform -chdir=terraform apply
	cd ansible && ansible-playbook playbook.yml
	@echo "======================================="
	@echo "РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО. АДРЕСА УЗЛОВ:"
	@echo "======================================="
	@echo 
	@terraform -chdir=terraform output -raw summary
	@echo 

ansible:
	cd ansible && ansible-playbook playbook.yml

	
terraform:
	terraform -chdir=terraform init
	terraform -chdir=terraform apply

destroy:
	terraform -chdir=terraform destroy
