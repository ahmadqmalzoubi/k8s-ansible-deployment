all:
  children:
    k8s_master:
      hosts:
        k8s-master:
          ansible_host: ${master_public_ip}
          private_ip: ${master_private_ip}
    k8s_workers:
      hosts:
%{ for index, ip in worker_public_ips ~}
        k8s-worker-${index + 1}:
          ansible_host: ${ip}
          private_ip: ${worker_private_ips[index]}
%{ endfor ~}
  vars:
    ansible_user: ${ssh_user}
    ansible_ssh_private_key_file: ${ssh_key_path}
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"