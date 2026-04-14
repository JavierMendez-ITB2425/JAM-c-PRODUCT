data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

# --- INTERFACES DEL FIREWALL (NODO 1) ---
resource "aws_network_interface" "fw_wan" {
  subnet_id         = aws_subnet.public.id
  security_groups   = [aws_security_group.sg_firewall.id]
  source_dest_check = false
  tags = { Name = "FW-eth0-WAN" }
}

resource "aws_network_interface" "fw_lan_services" {
  subnet_id         = aws_subnet.private_services.id
  security_groups   = [aws_security_group.sg_servicios.id]
  source_dest_check = false
  tags = { Name = "FW-eth1-LAN-Servicios" }
}

resource "aws_network_interface" "fw_lan_soc" {
  subnet_id         = aws_subnet.private_soc.id
  security_groups   = [aws_security_group.sg_servicios.id]
  source_dest_check = false
  tags = { Name = "FW-eth2-LAN-SOC" }
}

# --- IP ELÁSTICA PARA EL FIREWALL ---
resource "aws_eip" "fw_eip" {
  domain            = "vpc"
  network_interface = aws_network_interface.fw_wan.id
  depends_on        = [aws_internet_gateway.igw]
}

# --- NODO 1: FIREWALL/ROUTER ---
resource "aws_instance" "firewall" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = var.key_name

  network_interface {
    network_interface_id = aws_network_interface.fw_wan.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.fw_lan_services.id
    device_index         = 1
  }
  network_interface {
    network_interface_id = aws_network_interface.fw_lan_soc.id
    device_index         = 2
  }

  tags = { Name = "Nodo1-Firewall" }
}

# --- RUTAS PRIVADAS HACIA LAS INTERFACES DEL FIREWALL ---
resource "aws_route_table" "rt_services" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_lan_services.id
  }
}
resource "aws_route_table_association" "assoc_services" {
  subnet_id      = aws_subnet.private_services.id
  route_table_id = aws_route_table.rt_services.id
}

resource "aws_route_table" "rt_soc" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_lan_soc.id
  }
}
resource "aws_route_table_association" "assoc_soc" {
  subnet_id      = aws_subnet.private_soc.id
  route_table_id = aws_route_table.rt_soc.id
}

# --- RESTO DE LOS NODOS ---
resource "aws_instance" "balancer" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private_services.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  tags = { Name = "Nodo2-Balancer" }
}

resource "aws_instance" "streaming" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.private_services.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  tags = { Name = "Nodo${count.index + 3}-Streaming" }
}

resource "aws_instance" "soc" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.private_soc.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  tags = { Name = "Nodo5-SOC" }
}
