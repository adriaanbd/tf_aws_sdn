output "jump_box_ip" {
    value = aws_instance.jump_box.public_ip
}

output "app_instance_ip" {
    value = aws_instance.app_instance.private_ip
}

output "ssh_key_path" {
  value = local_file.my_key_file.filename
}