.PHONY: start ansible terraform destroy
start:
	terraform -chdir=terraform init
	terraform -chdir=terraform apply
	sleep 5
	cd ansible && ansible-playbook playbook.yml

ansible:
	cd ansible && ansible-playbook playbook.yml

	
terraform:
	terraform -chdir=terraform init
	terraform -chdir=terraform apply

destroy:
	terraform -chdir=terraform destroy
