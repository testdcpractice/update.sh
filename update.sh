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
    echo "$var_value"
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
        ls $WORK_DIR/dppm/planr_old | grep -w planr
        if [ $? -eq 0 ]; then
          mv -f $WORK_DIR/dppm/planr_old/planr $WORK_DIR/dppm/planr_old/planr_$(date +%y%m%d_%H:%M)
          if [ $? -eq 0 ]; then
            echo "Ранее созданная директория $WORK_DIR/dppm/planr_old/planr переименована в planr_$(date +%y%m%d%_H:%M)"
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

# С помощью grep получаем строки, которые отличаются и сохраняем их в var_temp
#-F обрабатывает строки как фиксированные (без регулярных выражений)
#-x сопоставляет только строки целиком
#-i игнорирует регистр
#-v выводит строки, которые не совпадают
#-f задаёт шаблон
var_temp=$(grep -Fxiv -f $WORK_DIR/dppm/planr/.env $WORK_DIR/dppm/planr_old/planr/.env)

#Чтение строк из var_file
#IFS= отключает разделение строки на отдельные поля, убирает пробелы из строки
#read —r читает строку из temp_file и сохраняет её в переменной replace_line
#-r флаг отключает обработку символов экранирования
#cut команда для извлечения части строки. флаг -d устанавливает '=' в качестве разделителя
#флаг -f 1 указывает, что извлекается строка до символа '=', а не после
#sed -i заменяет строку в файле .env
while IFS= read -r replace_line; do
  # Получаем имя переменной (ключ) из строки
  var_name=$(echo "$replace_line" | cut -d '=' -f 1)
  
  # Выполнение замены для каждой строки
  sed -i "s/^$var_name=.*/$replace_line/" $WORK_DIR/dppm/planr/.env
#Оператор <<< передаёт строку как стандартный ввод stdin в цикл while  
done <<< "$var_temp"

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
