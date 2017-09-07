#!/usr/bin/env bash

#Shell Script para fazer o dump backup paralelo
#Foi baseado na shell mysql-parallel (https://github.com/deviantintegral/mysql-parallel)
#E alterada por Ivaney Sales em 21/09/2015

# -----------------------------------------------------------------------------
# Variaveis
# -----------------------------------------------------------------------------
export NOME_DA_SHELL=`basename $0`

# -----------------------------------------------------------------------------
# Help da shell
# -----------------------------------------------------------------------------
function PrintUsage() {
  echo "Uso: $NOME_DA_SHELL [opcoes]..."
  echo "Exemplos:"
  echo "   $NOME_DA_SHELL -d /dados/backup"
  echo "     # Restatura os bancos de dados salvo no diretorio /dados/backup"
  echo "Opcoes:"
  echo "   -d  Diretorio do backup. Local de onde os arquivos serao restaturados."
  echo "   -u  Usuario do banco de dados. Se omitido serah usado o usuario do" 
  echo "       Sistema."
  echo "   -h  Nome do host ou IP do banco de dados. Se omitido serah usado o"
  echo "       localhost"
  echo "   -p  Senha do banco de dados."
  echo "   -P  Porta do banco de dados. Valor default 3306"

  exit 1
}

# -----------------------------------------------------------------------------
# Captura as opcoes e paramentros
# -----------------------------------------------------------------------------
while getopts "d:u:h:p:P:" OPTION
do
  case $OPTION in
    d) DESTINATION="$OPTARG"
       ;;
    u) USER="$OPTARG"
       ;;
    h) HOST="$OPTARG"
       ;;
    p) PASSWORD="$OPTARG"
       ;;
    P) PORT="$OPTARG"
       ;;
    ?) PrintUsage
       ;;
  esac
done

shift $((OPTIND-1))

RESTO="$1"

# -----------------------------------------------------------------------------
# Validar nossos arugments e garantir que GNU PARALLEL e pigz estao instalados
# -----------------------------------------------------------------------------
if [[ ! -z "$RESTO" ]]
then
  PrintUsage
fi

if [[ -z $DESTINATION ]]
then
  >&2 echo "Erro: O diretorio de backup nao foi informado"
  exit 1
fi

if [[ -z $USER ]]
then
  USER=`whoami`
fi

if [[ -z $HOST ]]
then
  HOST='localhost'
fi

if [[ -z $PASSWORD ]]
then
  PASSOPT=""
else
  PASSOPT="-p$PASSWORD"
fi

if [[ -z $PORT ]]
then
  PORT=3306
fi

PARALLEL=`type -P parallel`
if [[ -z $PARALLEL ]]
then
  >&2 echo "GNU Parallel eh requerido. Instale a partir do seu gerenciador de"
  >&2 echo "pacotes ou de https://savannah.gnu.org/projects/parallel/"
  exit 1
fi

GZIP=`type -P pigz`
if [[ -z $GZIP ]]
then
  >&2 echo "pigz was not found. Falling back to gzip. Consider installing pigz for improved"
  >&2 echo "performance."
  GZIP=`type -P gzip`
fi

OPTMYSQL="-u $USER -h$HOST -P$PORT  $PASSOPT "

# -----------------------------------------------------------------------------
# Restatura os bancos de dados
# -----------------------------------------------------------------------------
cd $DESTINATION
DIR_ORIGEM=`cd -`

DATABASES=`find * -type d | xargs`

for BANCO in $DATABASES
do
  echo "Restore $BANCO"
  echo "$DIR_ORIGEM"
  cd $DIR_ORIGEM
  cd $DESTINATION/$BANCO/
  time ls -S *.sql.gz | 
    $PARALLEL -I, echo "--Importing table ,." \&\&  $GZIP -kcd , \| mysql $OPTMYSQL $BANCO
done
