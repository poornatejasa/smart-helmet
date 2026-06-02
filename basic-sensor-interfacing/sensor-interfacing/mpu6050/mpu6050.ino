#include <Wire.h>
#include <MPU6050.h>

MPU6050 mpu;

float acc_mag;
float gyro_mag;

#define ACC_THRESHOLD   25000.0
#define GYRO_THRESHOLD  30000.0
#define COOLDOWN_MS     5000

unsigned long lastFallTime = 0;

void setup() {
  Serial.begin(9600);
  Wire.begin();
  mpu.initialize();
  if (mpu.testConnection())
    Serial.println("MPU6050 Connected");
  else
    Serial.println("Connection Failed");
}

void loop() {
  int16_t ax, ay, az;
  int16_t gx, gy, gz;

  mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

  acc_mag = sqrt((float)ax * ax +(float)ay * ay +(float)az * az);
  gyro_mag = sqrt((float)gx * gx +(float)gy * gy +(float)gz * gz);

  Serial.print("Acc: ");
  Serial.print(acc_mag);
  Serial.print("\tGyro: ");
  Serial.println(gyro_mag);

  if (acc_mag > ACC_THRESHOLD && gyro_mag > GYRO_THRESHOLD && millis() - lastFallTime > COOLDOWN_MS) {
    Serial.println("FALL DETECTED");
    lastFallTime = millis();
  }
  delay(100);
}