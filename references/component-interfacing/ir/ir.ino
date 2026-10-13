#define IR_PIN A3

void setup() {
  Serial.begin(9600);
  while (!Serial);
  pinMode(IR_PIN, INPUT);

}

void loop() {
  Serial.print("IR Value : ");
  Serial.println(analogRead(IR_PIN));
  delay(500);
}
