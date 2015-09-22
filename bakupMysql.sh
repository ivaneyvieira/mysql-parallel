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
  echo "Uso: $NOME_DA_SHELL [opcoes]... [bancos de dados]..."
  echo "Exemplos:"
  echo "   $NOME_DA_SHELL -d /dados/backup sqldados sqlpdv "
  echo "     # Faz o backup dos bancos sqldados e sqlpdv no diretorio"
  echo "       /dados/backup "
  echo "Opcoes:"
  echo "   -d  Diretorio de destino. Local onde os arquivos serao descaregados."
  echo "       Este diretorio deverah estah vazio."
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

DATABASES="$*"

# -----------------------------------------------------------------------------
# Validar nossos arugments e garantir que GNU PARALLEL e pigz estao instalados
# -----------------------------------------------------------------------------
if [[ -z "$DATABASES" ]]
then
  >&2 echo "Erro: Banco de dados nao informado"
  PrintUsage
fi

if [[ -z $DESTINATION ]]
then
  >&2 echo "Erro: O diretorio destino nao foi informado"
  exit 1
fi

mkdir -p $DESTINATION

if [ "$(ls -A $DESTINATION)" ]
then
  >&2 echo "Erro: $DESTINATION nao estah vazio"
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
# Salva a posicao da replicacao 
# -----------------------------------------------------------------------------
SHOW_MASTER_STATUS=`mysql --batch --skip-column-names $OPTMYSQL -e "show master status"`

MASTER_LOG_FILE=`echo $SHOW_MASTER_STATUS | awk '{print $1}'`
MASTER_LOG_POS=`echo $SHOW_MASTER_STATUS | awk '{print $2}'`

echo "CHANGE MASTER TO 
      MASTER_LOG_FILE='$MASTER_LOG_FILE', 
      MASTER_LOG_POS=$MASTER_LOG_POS;" > $DESTINATION/master_data.sql

# -----------------------------------------------------------------------------
# Faz o backup dos bacos de dados 
# -----------------------------------------------------------------------------
for BANCO in $DATABASES
do
  echo "Backup do banco $BANCO"
  # Recupera o nome de todas as tabelas
  TABLES=`mysql --batch --skip-column-names $OPTMYSQL \
                -e "show full tables where Table_Type = 'BASE TABLE'" $BANCO \
          |  awk '{print $1}'`
  if [[ -z $TABLES ]]
  then
    2> echo "Erro: Nao consigo obter tabelas do $BANCO. Verifique as suas opções de conexão"
    exit 1
  fi
  
  DIR_BANCO="$DESTINATION/$BANCO"
  mkdir -p "$DIR_BANCO"
  
  echo "--Dumping routines & triggers"
  mysqldump --routines --triggers --no-create-info --no-data \
    --no-create-db --skip-opt $BANCO 2> /dev/null \
    > $DIR_BANCO/routines.sql

  # Run one job for each table we are dumping.
  time echo $TABLES |
    $PARALLEL -d ' ' --trim=rl -I ,  echo "--Dumping table ,." \&\& \
      mysqldump -C $OPTMYSQL --skip-lock-tables --add-drop-table \
      --skip-routines --skip-triggers \
      $BANCO  , \| $GZIP \> $DIR_BANCO/,.sql.gz
done






