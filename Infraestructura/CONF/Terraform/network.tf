resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "VPC-Estadio" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "IGW-Estadio" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Subnet-Firewall-WAN" }
}

resource "aws_subnet" "visitantes" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Subnet-Visitantes" }
}

resource "aws_subnet" "gestion" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Subnet-Gestion" }
}

resource "aws_subnet" "soc" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Subnet-SOC" }
}

# ── NUEVO — Subnet DMZ ────────────────────────────────────
resource "aws_subnet" "dmz" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Subnet-DMZ" }
}

# Subnet pública del firewall sale por IGW
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "RT-Public" }
}

resource "aws_route_table_association" "assoc_public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt_public.id
}

# Las subredes privadas apuntan a la ENI del firewall
resource "aws_route_table" "rt_visitantes" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_wan.id
  }
  tags = { Name = "RT-Visitantes" }
}

resource "aws_route_table_association" "assoc_visitantes" {
  subnet_id      = aws_subnet.visitantes.id
  route_table_id = aws_route_table.rt_visitantes.id
}

resource "aws_route_table" "rt_gestion" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_wan.id
  }
  tags = { Name = "RT-Gestion" }
}

resource "aws_route_table_association" "assoc_gestion" {
  subnet_id      = aws_subnet.gestion.id
  route_table_id = aws_route_table.rt_gestion.id
}

resource "aws_route_table" "rt_soc" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.fw_wan.id
  }
  tags = { Name = "RT-SOC" }
}

resource "aws_route_table_association" "assoc_soc" {
  subnet_id      = aws_subnet.soc.id
  route_table_id = aws_route_table.rt_soc.id
}

# ── NUEVO — DMZ sale directamente por IGW ─────────────────
# No pasa por el firewall — acceso directo desde internet
# Esto es lo que la diferencia del resto de subredes
resource "aws_route_table" "rt_dmz" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "RT-DMZ" }
}

resource "aws_route_table_association" "assoc_dmz" {
  subnet_id      = aws_subnet.dmz.id
  route_table_id = aws_route_table.rt_dmz.id
}