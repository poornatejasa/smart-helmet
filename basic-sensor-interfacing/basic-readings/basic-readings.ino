#include <Wire.h>
#include <MPU6050.h>

MPU6050 mpu;

float acc_mag;
float gyro_mag;

#define ACC_THRESHOLD   25000.0
#define GYRO_THRESHOLD  30000.0
#define COOLDOWN_MS     5000
#define ALCOHOL_PIN A3
#define IR_PIN A2

unsigned long lastFallTime = 0;

void mpu6050_init(){
    Wire.begin();

    mpu.initialize();

    if (mpu.testConnection())
        Serial.println("MPU6050 Connected");
    else
        Serial.println("MPU6050 Connection Failed");
}
void mq3_sensor_init(){
  pinMode(ALCOHOL_PIN, INPUT);
}
void mpu6050_run(){
    int16_t ax, ay, az;
    int16_t gx, gy, gz;

    mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

    acc_mag = sqrt(
        (float)ax * ax +
        (float)ay * ay +
        (float)az * az
    );

    gyro_mag = sqrt(
        (float)gx * gx +
        (float)gy * gy +
        (float)gz * gz
    );

    Serial.print("Acc: ");
    Serial.print(acc_mag);
    Serial.print("\tGyro: ");
    Serial.println(gyro_mag);

    if (acc_mag > ACC_THRESHOLD &&
        gyro_mag > GYRO_THRESHOLD &&
        millis() - lastFallTime > COOLDOWN_MS)
    {
        Serial.println("FALL DETECTED");
        lastFallTime = millis();
    }
}
int mq3_sensor_run(){
  return analogRead(ALCOHOL_PIN);
}

void setup(void) {
  Serial.begin(9600);
  while (!Serial);
  mpu6050_init();
  mq3_sensor_init();
}

void loop() {
  mpu6050_run();
  int x = mq3_sensor_run();
  if(x>400){
    Serial.print("Alcohol Detected");
    Serial.println(x);
  }
  else{
    Serial.print("Alcohol Not Detected");
    Serial.println(x);
  }
  delay(500);
}