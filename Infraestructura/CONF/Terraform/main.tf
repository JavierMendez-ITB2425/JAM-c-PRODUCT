data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

# ─────────────────────────────────────────────────────────
# ENI DEL FIREWALL — una sola, source_dest_check=false
# es lo que permite actuar como router
# ─────────────────────────────────────────────────────────
resource "aws_network_interface" "fw_wan" {
  subnet_id         = aws_subnet.public.id
  security_groups   = [aws_security_group.sg_firewall.id]
  source_dest_check = false
  tags = { Name = "FW-eth0-WAN" }
}

resource "aws_eip" "fw_eip" {
  domain            = "vpc"
  network_interface = aws_network_interface.fw_wan.id
  depends_on        = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────────────────────
# NODO FIREWALL / ROUTER (Ahora también albergará Suricata)
# ─────────────────────────────────────────────────────────
resource "aws_instance" "firewall" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  network_interface {
    network_interface_id = aws_network_interface.fw_wan.id
    device_index         = 0
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # 1. Activar forwarding
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # 2. NAT — enmascara con la IP publica del firewall
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # 3. Permitir trafico de vuelta de conexiones ya establecidas
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 4. Reglas entre subredes
    # Visitantes → Gestion (replays, streaming) PERMITIDO
    iptables -A FORWARD -s 10.0.3.0/24 -d 10.0.4.0/24 -p tcp --dport 80   -j ACCEPT
    iptables -A FORWARD -s 10.0.3.0/24 -d 10.0.4.0/24 -p tcp --dport 8000 -j ACCEPT
    iptables -A FORWARD -s 10.0.3.0/24 -d 10.0.4.0/24 -p tcp --dport 1935 -j ACCEPT

    # Visitantes → SOC BLOQUEADO
    iptables -A FORWARD -s 10.0.3.0/24 -d 10.0.6.0/24 -j DROP

    # Gestion ↔ SOC PERMITIDO (agentes Wazuh, Prometheus scraping)
    iptables -A FORWARD -s 10.0.4.0/24 -d 10.0.6.0/24 -j ACCEPT
    iptables -A FORWARD -s 10.0.6.0/24 -d 10.0.4.0/24 -j ACCEPT

    # Todo lo demas dentro de la VPC puede salir a internet por el firewall
    iptables -A FORWARD -s 10.0.0.0/16 -j ACCEPT

    # 5. Persistir reglas
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    netfilter-persistent save
  EOF

  tags = { Name = "Nodo1-Firewall-IDS" }
}

# ─────────────────────────────────────────────────────────
# SUBNET VISITANTES (10.0.3.0/24)
# ─────────────────────────────────────────────────────────
resource "aws_instance" "portal_cautivo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.visitantes.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  tags = { Name = "Visitantes-Nginx-Portal" }
}

resource "aws_instance" "iperf" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.visitantes.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  tags = { Name = "Visitantes-iPerf3" }
}

# ─────────────────────────────────────────────────────────
# SUBNET GESTION/BROADCAST (10.0.4.0/24)
# ─────────────────────────────────────────────────────────
resource "aws_instance" "balanceador_gestion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.gestion.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  private_ip             = "10.0.4.242"
  tags = { Name = "Gestion-Balanceador" }
}

resource "aws_instance" "icecast" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.gestion.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  private_ip             = "10.0.4.195"
  tags = { Name = "Gestion-HLS1" }
}

resource "aws_instance" "ftp" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.gestion.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  private_ip             = "10.0.4.166"
  tags = { Name = "Gestion-HLS2" }
}

# ─────────────────────────────────────────────────────────
# SUBNET SOC (10.0.6.0/24)
# ─────────────────────────────────────────────────────────
resource "aws_instance" "soc_core" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large" # Consolidado para Docker: Wazuh, TheHive, Grafana, Prometheus
  subnet_id              = aws_subnet.soc.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 50 # Recomendable aumentar el disco para logs y BBDD
    volume_type = "gp3"
  }

  tags = { Name = "SOC-Core-Docker" }
}

# ── Subnet DMZ ────────────────────────────────────────────
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.dmz.id
  vpc_security_group_ids = [aws_security_group.sg_dmz.id]
  key_name               = var.key_name
  private_ip             = "10.0.5.50"
  tags = { Name = "DMZ-WebServer" }
}


# ── Base de Datos — Subnet Gestión ───────────────────────
resource "aws_instance" "database" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.gestion.id
  vpc_security_group_ids = [aws_security_group.sg_servicios.id]
  key_name               = var.key_name
  private_ip             = "10.0.4.10"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "Gestion-MySQL" }
}


# ─────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────
output "firewall_ip_publica" {
  value = aws_eip.fw_eip.public_ip
}

output "ips_privadas" {
  value = {
    visitantes_portal   = aws_instance.portal_cautivo.private_ip
    visitantes_iperf    = aws_instance.iperf.private_ip
    gestion_balanceador = aws_instance.balanceador_gestion.private_ip
    gestion_icecast     = aws_instance.icecast.private_ip
    gestion_ftp         = aws_instance.ftp.private_ip
    soc_core_docker     = aws_instance.soc_core.private_ip
    dmz_web_server      = aws_instance.web_server.private_ip
    gestion_database    = aws_instance.database.private_ip
  }
}
