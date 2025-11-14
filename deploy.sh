#!/bin/bash
# ==================================
# 무중단 배포 스크립트 (Blue/Green)
# ==================================

echo "===== 무중단 배포 시작 ====="

# 1. .yml로부터 JAVA_HOME 경로 받기
JAVA_HOME_ARG=$1
if [ -z "$JAVA_HOME_ARG" ]; then
    echo "오류: JAVA_HOME이 .yml에서 전달되지 않았습니다. 기본 'java'를 사용합니다."
    JAVA_CMD="/usr/local/java/java21/bin/java"
else
    echo "Using JAVA_HOME from .yml: $JAVA_HOME_ARG"
    JAVA_CMD="$JAVA_HOME_ARG/bin/java"

    # 해당 경로에 java 파일이 있는지 확인
    if [ ! -f "$JAVA_CMD" ]; then
        echo "오류: $JAVA_CMD 를 찾을 수 없습니다. 기본 'java'를 사용합니다."
        JAVA_CMD="java"
    fi
fi
echo "Using Java command: $JAVA_CMD"


# 2. 상수 정의
JAR_FILE_NAME="Book2OnAndOn-book-service-0.0.1-SNAPSHOT.jar"
JAR_PATH="$HOME/$JAR_FILE_NAME"
PROFILE="prod"

# 3. 배포할 JAR 파일 확인
echo "배포할 JAR 파일 확인: $JAR_PATH"
if [ ! -f "$JAR_PATH" ]; then
    echo "오류: JAR 파일($JAR_PATH)을 찾을 수 없습니다. 배포를 중단합니다."
    ls -la $HOME/*.jar
    exit 1
fi

# 4. 현재 실행 중인 포트 확인
CURRENT_PID_10421=$(lsof -ti:10421 2>/dev/null)
CURRENT_PID_10422=$(lsof -ti:10422 2>/dev/null)


# 5. 새로 배포할 포트 결정
if [ -n "$CURRENT_PID_10421" ]; then
    NEW_PORT=10422
    OLD_PORT=10421
    OLD_PID=$CURRENT_PID_10421
    echo "[Switch] 10421(Running) -> 10422(New)"
elif [ -n "$CURRENT_PID_10422" ]; then
    NEW_PORT=10421
    OLD_PORT=10422
    OLD_PID=$CURRENT_PID_10422
    echo "[Switch] 10422(Running) -> 10421(New)"
else
    NEW_PORT=10421
    OLD_PORT=""
    OLD_PID=""
    echo "[Start] 10421 포트로 첫 인스턴스 시작"
fi

#6. 새 버전 배포
LOG_PATH="$HOME/app-${NEW_PORT}.log"
echo "새 애플리케이션을 $PROFILE 프로필, $NEW_PORT 포트에서 시작합니다..."


if [  -f "$LOG_PATH" ]; then
	echo "기존 로그 파일($LOG_PATH)을 백업합니다: ${LOG_PATH}.old"
    	mv $LOG_PATH ${LOG_PATH}.old
fi
# 'java' 대신 '$JAVA_CMD' 사용, '>>' (append) 사용
nohup $JAVA_CMD -jar \
    -Dspring.profiles.active=$PROFILE \
    -Dserver.port=$NEW_PORT \
    $JAR_PATH >> $LOG_PATH 2>&1 &

NEW_PID=$!
echo "새 애플리케이션 PID: $NEW_PID"

# 7. Health check (최대 60초 대기)
echo "애플리케이션 시작 대기 중... (최대 60초)"
sleep 20 # sleep 30 대신 15초로 변경 (test.sh와 동일하게)

SUCCESS=false

for i in {1..30}; do
    # 프로세스가 죽었는지 확인
    if ! kill -0 $NEW_PID 2>/dev/null; then
        echo "❌ 새 애플리케이션 프로세스가 종료되었습니다!"
        echo "=== 최근 로그 ==="
        tail -30 $LOG_PATH
        exit 1
    fi
    
    # Health check (actuator 사용)
    if curl -f -s http://localhost:$NEW_PORT/actuator/health > /dev/null 2>&1; then
        echo "✅ Health check 성공! (actuator/health)"
        SUCCESS=true
        break
    fi
    
    # 기본 엔드포인트도 체크
    if curl -f -s http://localhost:$NEW_PORT/ > /dev/null 2>&1; then
        echo "✅ Health check 성공! (root endpoint)"
        SUCCESS=true
        break
    fi

    echo "⏳ Health check 시도 $i/30..."
    sleep 3
done

# Health check 실패 처리
if [ "$SUCCESS" = false ]; then
    echo "❌ Health check 실패!"
    echo "=== 최근 로그 ==="
    tail -50 $LOG_PATH
    echo ""
    echo "배포 실패. 새 프로세스를 종료합니다."
    kill -15 $NEW_PID 2>/dev/null
    exit 1
fi

# 8. 이전 버전 종료
if [ -n "$OLD_PID" ]; then
    echo "이전 애플리케이션(PID: $OLD_PID, Port: $OLD_PORT) 종료 중..."
    kill -15 $OLD_PID 2>/dev/null
    sleep 2
    
    # 강제 종료가 필요하면
    if kill -0 $OLD_PID 2>/dev/null; then
        echo "강제 종료 중..."
        kill -9 $OLD_PID 2>/dev/null
    fi
    echo "이전 애플리케이션 종료 완료"
fi

echo "===== 무중단 배포 완료 ====="
echo "✅ 현재 실행 중인 포트: $NEW_PORT (PID: $NEW_PID)"
