package agent

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"path"
	"strconv"
	"time"

	"k8s.io/klog"
)

func startClient(server, caFile, certFile, keyFile, serverName string) error {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return fmt.Errorf("Failed to load X509 key pair: %v", err)
	}

	// Load CA Certificate for client certificate verification
	caCert, err := ioutil.ReadFile(path.Clean(caFile))
	if err != nil {
		return fmt.Errorf("Failed to read root certificate file: %v", err)
	}

	caPool := x509.NewCertPool()
	if ok := caPool.AppendCertsFromPEM(caCert); !ok {
		return fmt.Errorf("failed to add certificate from ca.crt")
	}

	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientCAs:    caPool,
		ServerName:   serverName, //CN: common name
	}

	klog.Info("Connecting to server: " + server)
	conn, err := tls.Dial("tcp", server, tlsCfg)
	if err != nil {
		return fmt.Errorf(err.Error())
	}

	defer conn.Close()
	klog.Info("Connected to ", conn.RemoteAddr())

	conn.Write([]byte(nodeName))

	ticker := time.NewTicker(1 * time.Second * 30)
	defer ticker.Stop()

	buf := make([]byte, 128)
	pos := 0
	for {
		select {
		case <-ticker.C:
			// ensure connection be alive
			if _, err = conn.Write([]byte("hello.")); err != nil {
				return fmt.Errorf(err.Error())
			}
		default:
			// the content of a request: JSON content size (8 byte) | JSON format content
			// JSON content: {"UID":"...","rcgroup":"..."
			size, err := conn.Read(buf[pos:])
			if err != nil {
				klog.Errorf("Failed to read: %v", err)
				return err
			}

			size += pos
			pos = size
			//ensure content size part is received at least
			if size <= 8 {
				continue
			}

			pos = 0
			// there may be multiple records + an incomplete record
			for {
				// check if the rest is an incomplete record
				if size <= 8 {
					pos = size
					break
				}

				jsize, _ := strconv.Atoi(string(buf[pos : pos+8]))

				if size < 8+jsize {
					copy(buf, buf[pos:pos+size])
					pos = size
					break
				}

				// process a record
				m := make(map[string]string)

				klog.Infof("Received: %s", buf[pos+8:pos+8+jsize])
				if err := json.Unmarshal(buf[pos+8:pos+8+jsize], &m); err != nil {
					klog.Errorf("Failed to parse data: %v", buf)
				}

				uid, ok := m["UID"]
				rcgroup, ok2 := m["rcgroup"]
				if !ok || !ok2 {
					return fmt.Errorf("Wrong data: %v", buf)
				}

				assignControlGroup(uid, rcgroup)
				pos += 8 + jsize
				size -= 8 + jsize
			}
		}
	}

	return nil
}
