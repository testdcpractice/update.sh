#Объявляем переменные
FILE_PATH=""
WORK_DIR=""
PASSWORD="planr"
SET_FILE=./.set
LOGGING_DIR=false
BACKUP=false
CRON_TASK=false

#Тестовый массив для сравнения директорий 
PLANR_STRUCTURE=(images planr)

#Функция, вывод справки по флагам
function help() {
  echo ""  
  echo -e "    \033[1mФлаги:\033[0m"  
  echo "    -f    Директория в которой находится архив с дистрибутивом или установочные файлы"
  echo "    -w    Директория развёртывания"
  echo "    -b    Создание бэкапа базы данных на текущий момент. Установите в значение true(по умолчанию, false)"
  echo "    -l    Если, LOGGING_DIR=true, то каталоги и конфигурации fluent-bit и loki не обновляются"
  echo "    -c    Если, CRON_TASK=true, создаётся запись в планировщике crontab для периодического бэкапа базы данных"
  echo "    -h    Справка"
}

#Функция, которая проверяет, переданы ли в скрипт значения переменных.
check_var() {
  declare var_name=$1
  # Получение значения переменной по её имени
  declare var_value=${!var_name}  

  if [[ -z "$var_value" ]]; then
    echo "Ошибка! Не присвоено значение переменной $var_name в файле $SET_FILE или аргументу флага"
    exit 1
  else
    echo "$var_name=$var_value"
  fi
}

#Функция, которая создаёт директорию planr_old
function create_planr_old_dir() {   
  #Проверка наличия архива с дистрибутивом или папки
  # c распакованным дистрибутивом
  if [ -e $FILE_PATH ]; then
    #Проверка,что директория WORK_DIR существует
    if [ -d $WORK_DIR ]; then
      #Проверка, существует ли в целевой директории, ранее созданная папка planr_old
      if [ -d $WORK_DIR/dppm/planr_old ]; then
        echo "Обнаружена ранее созданная директория $WORK_DIR/dppm/planr_old/"
        #grep -w: флаг -w означает, что grep ищет точное совпадение
        ls $WORK_DIR/dppm/planr_old | grep -w planr > /dev/null
        if [ $? -eq 0 ]; then
          mv -f $WORK_DIR/dppm/planr_old/planr $WORK_DIR/dppm/planr_old/planr_$(date +%y%m%d_%H:%M)
          if [ $? -eq 0 ]; then
            echo "Ранее созданная директория $WORK_DIR/dppm/planr_old/planr переименована в planr_$(date +%y%m%d_%H:%M)"
          else
            echo "Ошибка! Не удалось переименовать директорию $WORK_DIR/dppm/planr_old/planr"
            exit 1
          fi
        fi          
      else
        #Создадим папку planr_old в директории $WORK_DIR/dppm/
        mkdir $WORK_DIR/dppm/planr_old
        #проверка создания каталога planr_old
        if [ $? -eq 0 ]; then
          echo "Каталог $WORK_DIR/dppm/planr_old создан"
        else
          echo "Ошибка! Не удалось создать каталог planr_old"
          exit 1
        fi    
      fi      
    else
      echo "Ошибка! Директория развёртывания не существует"
      exit 1
    fi
  else
    echo "Ошибка! Архив с дистрибутивом или установочные файлы не найдены в указаной директории $FILE_PATH"
    exit 1
  fi  
}

#Функция парсит .env файл в ассоциативный массив
function parse_env() {
  #Объявляем ассоциативный массив с глобальной видимостью
  declare -gA env_array
  sed -i '$a\' $1
  while IFS= read -r line; do
    #Пропуск пустых строк и комментариев
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      continue
    fi

    #Проверяем, что строка содержит =
    if [[ "$line" == *=* ]]; then
      #Получаем ключ из строки
      key=$(echo "$line" | cut -d '=' -f 1)
      #Получаем значение из строки
      value=$(echo "$line" | cut -d '=' -f 2)
      #Добавляем в ассоциатинвый массив ключи и значения
      env_array["$key"]="$value"
    fi
  done < "$1"
}

#Функция для замены строки в файле .env
function replace_line_in_file() {
  local file="$1"
  local line_num="$2"
  local replacement="$3"

  replacement_escaped=$(echo "$replacement" | sed -e 's/[\/&]/\\&/g')
  #Замена строки в файле
  sed -i "${line_num}s/.*/$replacement_escaped/" "$file"
}

#Функция добавляет новую строку в файл .env
function add_new_line_to_file() {
  local file="$1"
  local new_line="$2"
  #Добавление новой строки в конец файла. tee -a добавляет строку с переносом на новую строку
  echo "$new_line" | tee -a "$file"
}

#Функция, которая ищет различия в папках planr и /planr_old/planr и добавляет
#недостающие файли или папки из /planr_old/planr в planr
function sync_diff_planr() {
  local planr_new=$1
  local planr_old=$2

  #Команда diff для нахождения различий
  diff_output=$(diff -r "$planr_new" "$planr_old")

  #Если diff находит различия, копируем недостающие файлы или папки из planr_old в planr_new
  if [[ ! -z "$diff_output" ]]; then
    #rsync -av --ignore-existing копирует, только недостающие файлы или папки
    rsync -av --ignore-existing "$planr_old/" "$planr_new/" > /dev/null
    echo "Недостающие файлы и папки из "$planr_old" были скопированы в "$planr_new""
  else
    echo "Между "$planr_new" и  "$planr_old" различий не обнаружено"
  fi
}

#Передача параметров командной строки в скрипт с помощью флагов  
while getopts "f:w:b:l:c:h" Option
do
  case $Option in
    f     )
            if [ ! -e "$OPTARG" ]; then
              echo "Ошибка! Архив с дистрибутивом или установочные файлы не найдены в указанной директории $OPTARG"
              exit 1
            fi
            FILE_PATH=$OPTARG;;  
    w     )
            if [ ! -d "$OPTARG" ]; then
              echo "Ошибка! $OPTARG не создан или это не директория"
              exit 1
            fi
            WORK_DIR=$OPTARG;;
    b     )
            if [[ "$OPTARG" != "true" && "$OPTARG" != "false" ]]; then
              echo "Ошибка! Не присвоенно значение true или false флагу -b"
              exit 1
            fi
            BACKUP=$OPTARG;;
    l     )
            if [[ "$OPTARG" != "true" && "$OPTARG" != "false" ]]; then
              echo "Ошибка! Не присвоенно значение true или false флагу -l"
              exit 1
            fi
            LOGGING_DIR=$OPTARG;;
    c     )
            if [[ "$OPTARG" != "true" && "$OPTARG" != "false" ]]; then
                echo "Ошибка! Значение флага -c должно быть true или false"
                exit 1
            fi
            CRON_TASK=$OPTARG;;
    h     )
            help
            exit 1;;                                         
    *     )
            echo "Ошибка! Неизвестный флаг или флаг требует аргумента"
            help
            exit 1;;            
    esac
done

#xargs преобразует строки из файла .set в формат переменных окружения для export
#export экспортирует значения переменных в intsall.sh
export $(grep -v '^#' $SET_FILE | xargs) > /dev/null
if [ $? -eq 0 ]; then
  echo "Переменные окружения экспортированы из $SET_FILE"
else
  echo "Ошибка! Не удалось экспортировать переменные окружения из файла .set"
  exit 1
fi

check_var "FILE_PATH"
check_var "WORK_DIR"

#Создание бэкапа базы данных, перед обновлением
if [ ${BACKUP} = true ]; then
  if [ -d $WORK_DIR/dppm/planr/scripts ]; then
    #Переходим в директорию со скриптами
    cd $WORK_DIR/dppm/planr/scripts
    #./dump.sh создаст бэкап базы данных на текущий момент
    ./dump.sh -p $WORK_DIR/dppm/postgres_dump
    if [ $? -eq 0 ]; then
      echo "Бэкап базы данных успешно создан"
    else
      echo "Ошибка! Не удалось создать бэкап базы данных"
      exit 1  
    fi
  else
    echo "Ошибка! Не удалось найти директорию $WORK_DIR/dppm/planr/scripts"
    exit 1
  fi      
fi

#Проверка статуса: запущен Plan-R или нет
docker ps | grep planr > /dev/null
if [ $? -eq 0 ]; then
  echo "Ошибка! Перед обновлением Plan-R, необходимо остановить систему"
  echo "Выполните скрипт ./stop.sh в директории разворота"
  exit 1
fi  

#Проверка, есть ли старая папка images
ls $WORK_DIR/dppm | grep images > /dev/null
if [ $? -eq 0 ]; then
  #Удаляем старую images
  rm -r $WORK_DIR/dppm/images
fi

#Проверяем,является ли $FILE_PATH архивом
unzip -z $FILE_PATH &> /dev/null
if [ $? -eq 0 ]; then
  #Создаём директорию развёртывания
  create_planr_old_dir
  #Перенос текущего каталога разворота в planr_old
  mv $WORK_DIR/dppm/planr $WORK_DIR/dppm/planr_old
  if [ $? -eq 0 ]; then
    echo "Перенос текущего каталога разворота $WORK_DIR/dppm/planr в директорию $WORK_DIR/dppm/planr_old выполнен успешно"
  else
    echo "Ошибка! Не удалось выполнить перенос текущего каталога разворота в директорию planr_old"
    exit 1
  fi 
  #Перемещаем дистрибутив
  mv $FILE_PATH $WORK_DIR/dppm/distr/
  if [ $? -eq 0 ]; then
    echo "Дистрибутив перемещён в директорию $WORK_DIR/dppm/distr/"
  else
    echo "Ошибка! Не удалось переместить дистрибутив"
    exit 1  
  fi
  #Регулярное выражение с переменной FILE_PATH. dirname возвращает путь  
  #к каталогу DIR, в котором находится файл. basename только имя файла FILE, без пути
  DIR="$(dirname "${FILE_PATH}")/" ; FILE="$(basename "${FILE_PATH}")"

  #Извлечение файлов из архива
  echo "Извлечение файлов из архива"
  unzip -P $PASSWORD $WORK_DIR/dppm/distr/$FILE -d $WORK_DIR/dppm/
  if [ $? -eq 0 ]; then
    echo "Извлечение файлов из архива, выполнено успешно"
  else
    echo "Ошибка! Не удалось извлечь файлы из архива"
    exit 1
  fi  
else
  #Присваиваем содержимое $FILE_PATH, массиву current_structure, исключая файлы
  #с расширением *.tgz
  current_structure=($(ls -I "*.tgz" $FILE_PATH))
  if [ "${PLANR_STRUCTURE[*]}" == "${current_structure[*]}" ]; then
    #Создаём директорию развёртывания
    create_planr_old_dir
    #Перенос текущего каталога разворота в planr_old
    mv $WORK_DIR/dppm/planr $WORK_DIR/dppm/planr_old/
    if [ $? -eq 0 ]; then
      echo "Перенос текущего каталога разворота $WORK_DIR/dppm/planr в директорию $WORK_DIR/dppm/planr_old выполнен успешно"
    else
      echo "Ошибка! Не удалось выполнить перенос текущего каталога разворота в директорию planr_old"
      exit 1
    fi 
    #Перемещаем содержимое $FILE_PATH
    mv $FILE_PATH/* $WORK_DIR/dppm/
  else
    echo "Ошибка! Проверьте значение или содержимое FILE_PATH"
    exit 1 
  fi 
fi

#LOGGING_DIR=TRUE
if [ ${LOGGING_DIR} = true ]; then
  if [ -d $WORK_DIR/dppm/planr_old/planr/logging/fluent-bit ] && [ -d $WORK_DIR/dppm/planr/logging ]; then
    cp -r $WORK_DIR/dppm/planr_old/planr/logging/fluent-bit $WORK_DIR/dppm/planr/logging
    if [ $? -eq 0 ]; then
      echo "Текущая конфигурация fluent-bit не обновлялась, потому что LOGGING_DIR=true"
    else
      echo "Ошибка! Не удалось сохранить текущую конфигурацию fluent-bit"
      exit 1
    fi    
    cp -r $WORK_DIR/dppm/planr_old/planr/logging/loki $WORK_DIR/dppm/planr/logging
    if [ $? -eq 0 ]; then
      echo "Текущая конфигурация loki не обновлялась, потому что LOGGING_DIR=true"
    else
      echo "Ошибка! Не удалось сохранить текущую конфигурацию loki"
      exit 1
    fi    
  else
    echo "Ошибка! Не удалось переместить папки fluent-bit и loki в директорию $WORK_DIR/dppm/planr/logging"
    echo "Проверьте наличие и содержимое целевых каталогов"
  fi  
fi

#Загруза образов
echo "Загрузка образов"
cd $WORK_DIR/dppm/images/
./load.sh
if [ $? -eq 0 ]; then
  echo "Образы успешно загружены"     
else
  echo "Ошибка! Образы не загружены"
  exit 1
fi

#Вызываем функцию sync_diff_planr
sync_diff_planr $WORK_DIR/dppm/planr $WORK_DIR/dppm/planr_old/planr

#Парсим новый .env файл
parse_env $WORK_DIR/dppm/planr/.env

#Объявляем ассоц.массив env_array_new и заполняем его ключами env_array
declare -A env_array_new
for key in "${!env_array[@]}"; do
  env_array_new["$key"]="${env_array[$key]}"
done

#Парсим старый .env файл
parse_env $WORK_DIR/dppm/planr_old/planr/.env

#Объявляем ассоц.массив env_array_old и заполняем его ключами env_array
declare -A env_array_old
for key in "${!env_array[@]}"; do
  env_array_old["$key"]="${env_array[$key]}"
done

#Заполняем env_array_new данными из env_array_old
for key in "${!env_array_old[@]}"; do
  if [[ -z "${env_array_new[$key]}" || "${env_array_new[$key]}" != "${env_array_old[$key]}" ]]; then
    echo "Значение для ключа "$key" отличается, перезаписываем"
    env_array_new["$key"]="${env_array_old[$key]}"
  fi
done

#Обновление файла ./1/.env
line_counter=1
while IFS= read -r line || [[ -n "$line" ]]; do
  #Пропускаем комментарии
  if [[ "$line" == \#* ]]; then
    line_counter=$((line_counter + 1))
    continue
  fi

  #Проверяем, содержит ли строка символ =
  if [[ "$line" == *=* ]]; then
    key=$(echo "$line" | cut -d '=' -f 1)
    if [[ -n "${env_array_new[$key]}" ]]; then
      replace_line_in_file $WORK_DIR/dppm/planr/.env "$line_counter" "$key=${env_array_new[$key]}"
      unset env_array_new[$key]
    fi
  fi
  line_counter=$((line_counter + 1))
done < "$WORK_DIR/dppm/planr/.env"


#Добавляем ключи, которые есть в старом .env файле, но нет в новом
for key in "${!env_array_new[@]}"; do
  add_new_line_to_file "$WORK_DIR/dppm/planr/.env" "$key=${env_array_new[$key]}"
done

# Добавление задания в crontab, если флаг -c true
if [ ${CRON_TASK} = true ]; then
  grep "dump.sh" /etc/crontab > /dev/null
  if [ $? -eq 0 ]; then
    sed -i "/dump\.sh/c\0 3 * * * root $WORK_DIR/dppm/planr/scripts/dump.sh -c postgres -p $WORK_DIR/dppm/postgres_dump/ -r 14 -k 5" /etc/crontab
    echo "В crontab успешно добавлено новое задание для автоматического бэкапа базы данных"
  else
    #Комнда tee записывает вывод команды echo в файл /etc/crontab
    #флаг -a указывает, что строка добавляется в конец файла
    echo "0 3 * * * root $WORK_DIR/dppm/planr/scripts/dump.sh -c postgres -p $WORK_DIR/dppm/postgres_dump/ -r 14 -k 5" | tee -a /etc/crontab
    echo "В crontab успешно добавлено задание для автоматического бэкапа базы данных"  
  fi
fi 
