#define MOTOR_PIN A3

void setup() {
  pinMode(MOTOR_PIN, OUTPUT);

}

void loop() {
  analogWrite(MOTOR_PIN, 0);
  delay(500);
  analogWrite(MOTOR_PIN, 255);
  delay(500);
}
