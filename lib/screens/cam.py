import cv2

index = 0
while True:
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)  # Intenta usar DirectShow en Windows
    if not cap.isOpened():
        print(f"❌ No hay cámara en el índice {index}")
        break
    else:
        print(f"✅ Cámara detectada en el índice {index}")
    cap.release()
    index += 1
