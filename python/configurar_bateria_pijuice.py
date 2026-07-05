import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice

pj = PiJuice(1, 0x14)

# Configurar perfil custom para batería LiPo 10000mAh sin NTC
resultado = pj.config.SetCustomBatteryProfile({
    'capacity': 10000,
    'chargeCurrent': 2500,
    'terminationCurrent': 50,
    'regulationVoltage': 4160,
    'cutoffVoltage': 3000,
    'tempCold': 1,
    'tempCool': 10,
    'tempWarm': 45,
    'tempHot': 59,
    'ntcB': 0,
    'ntcResistance': 0
})
print(f"SetCustomBatteryProfile: {resultado}")

resultado2 = pj.config.SetBatteryProfile('CUSTOM')
print(f"SetBatteryProfile: {resultado2}")

print(f"Perfil activo: {pj.config.GetBatteryProfile()}")
print(f"Nivel de batería: {pj.status.GetChargeLevel()}")
