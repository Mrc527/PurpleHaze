package ch.visin.purplehaze.config;

import android.content.ContentValues;

/**
 * Wrapper around ContentValues in Database
 */
public class ConnectionProfile {
	public static enum NameserverMode {
		LEAVE_DEFAULT, SET_SERVER_TUNNEL_IP, SET_CUSTOM
	}

	public static enum RequestType {
		AUTODETECT, NULL, PRIVATE, TXT, SRV, MX, CNAME, A;

		public String getIodineName() {
			if (this == AUTODETECT) {
				return "";
			} else {
				return name();
			}
		}
	}

	private final ContentValues v;

	public ConnectionProfile() {
		v = new ContentValues();
	}

	public ConnectionProfile(ContentValues v) {
		this.v = v;
	}

	@Override
	public boolean equals(Object o) {
		if (o instanceof ConnectionProfile) {
			return this == o || getId() != null && getId().equals(((ConnectionProfile) o).getId());
		} else {
			return super.equals(o);
		}
	}

    @Override public int hashCode() { return getId() == null ? System.identityHashCode(this) : getId().hashCode(); }

	public Long getId() {
		return v.getAsLong(ProfileRepository.COLUMN_CONF_ID);
	}

	public boolean getDefaultRoute() {
		return v.getAsInteger(ProfileRepository.COLUMN_CONF_DEFAULT_ROUTE) == 1;
	}

	public void setDefaultRoute(boolean isDefaultRoute) {
		v.put(ProfileRepository.COLUMN_CONF_DEFAULT_ROUTE, isDefaultRoute ? 1 : 0);
	}

	public boolean getLazyMode() {
		return v.getAsInteger(ProfileRepository.COLUMN_CONF_LAZY_MODE) == 1;
	}

	public String getName() {
		return v.getAsString(ProfileRepository.COLUMN_CONF_NAME);
	}

	public String getNameserver() {
		return v.getAsString(ProfileRepository.COLUMN_CONF_NAMESERVER);
	}

	public NameserverMode getNameserverMode() {
		return NameserverMode.valueOf(v.getAsString(ProfileRepository.COLUMN_CONF_NAMESERVER_MODE));
	}

	public String getPassword() {
		return v.getAsString(ProfileRepository.COLUMN_CONF_PASSWORD);
	}

	public boolean getRawMode() {
		return v.getAsInteger(ProfileRepository.COLUMN_CONF_RAW_MODE) == 1;
	}

	public RequestType getRequestType() {
		return RequestType.valueOf(v.getAsString(ProfileRepository.COLUMN_CONF_REQUEST_TYPE));
	}

	public String getTopDomain() {
		return v.getAsString(ProfileRepository.COLUMN_CONF_TOP_DOMAIN);
	}

	public String getTunnelNameserver() {
		return v.getAsString(ProfileRepository.COLUMN_CONF_TUNNEL_NAMESERVER);
	}

	public void setLazyMode(boolean lazyMode) {
		v.put(ProfileRepository.COLUMN_CONF_LAZY_MODE, lazyMode ? 1 : 0);
	}

	public void setName(String name) {
		v.put(ProfileRepository.COLUMN_CONF_NAME, name);
	}

	public void setNameserver(String nameserver) {
		v.put(ProfileRepository.COLUMN_CONF_NAMESERVER, nameserver);
	}

	public void setNameserverMode(NameserverMode nameserverMode) {
		v.put(ProfileRepository.COLUMN_CONF_NAMESERVER_MODE, nameserverMode.name());
	}

	public void setPassword(String password) {
		v.put(ProfileRepository.COLUMN_CONF_PASSWORD, password);
	}

	public void setRawMode(boolean rawMode) {
		v.put(ProfileRepository.COLUMN_CONF_RAW_MODE, rawMode ? 1 : 0);
	}

	public void setRequestType(RequestType requestType) {
		v.put(ProfileRepository.COLUMN_CONF_REQUEST_TYPE, requestType.name());
	}

	public void setTopDomain(String topDomain) {
		v.put(ProfileRepository.COLUMN_CONF_TOP_DOMAIN, topDomain);
	}

	public void setTunnelNameserver(String tunnelNameserver) {
		v.put(ProfileRepository.COLUMN_CONF_TUNNEL_NAMESERVER, tunnelNameserver);
	}

	public void setId(Long id) {
		v.put(ProfileRepository.COLUMN_CONF_ID, id);
	}

	public ContentValues getContentValues() {
		return v;
	}

	public int getRequestHostnameSize() {
		return v.getAsInteger(ProfileRepository.COLUMN_CONF_REQUEST_HOSTNAME_SIZE);
	}

	public void setRequestHostnameSize(int requestHostnameFragmentSize) {
		v.put(ProfileRepository.COLUMN_CONF_REQUEST_HOSTNAME_SIZE, requestHostnameFragmentSize);
	}

	public int getResponseFragmentSize() {
		return v.getAsInteger(ProfileRepository.COLUMN_CONF_RESPONSE_FRAGMENT_SIZE);
	}

	public void setResponseFragmentSize(int responseFragmentSize) {
		v.put(ProfileRepository.COLUMN_CONF_RESPONSE_FRAGMENT_SIZE, responseFragmentSize);
	}

    public String getSharedKey() {
        String value = v.getAsString(ProfileRepository.COLUMN_CONF_SHARED_KEY);
        return value == null ? "" : value;
    }
    public boolean getProxy() {
        Integer value = v.getAsInteger(ProfileRepository.COLUMN_CONF_PROXY);
        return value != null && value == 1;
    }

    public int getRequestTimeout() { Integer x = v.getAsInteger("request_timeout"); return x == null ? 1 : x; }
    public void setRequestTimeout(int x) { v.put("request_timeout", x); }
    public String getDownstreamEncoding() { String x = v.getAsString("downstream_encoding"); return x == null ? "" : x; }
    public void setDownstreamEncoding(String x) { v.put("downstream_encoding", x); }
    public boolean getIpv6Transport() { Integer x = v.getAsInteger("ipv6_transport"); return x != null && x == 1; }
    public void setIpv6Transport(boolean x) { v.put("ipv6_transport", x ? 1 : 0); }
    public boolean isEncrypted() { Integer value = v.getAsInteger("encrypted"); return value == null ? !getSharedKey().trim().isEmpty() : value == 1; }
    public void setEncrypted(boolean value) { v.put("encrypted", value ? 1 : 0); }
    public static ConnectionProfile create() {
        ConnectionProfile p = new ConnectionProfile();
        p.setEncrypted(true); p.setName(""); p.setTopDomain(""); p.setPassword(""); p.setTunnelNameserver("");
        p.setNameserverMode(NameserverMode.SET_CUSTOM); p.setNameserver("1.1.1.1");
        p.setRequestType(RequestType.AUTODETECT); p.setLazyMode(true); p.setRawMode(false);
        p.setDefaultRoute(true); p.setRequestHostnameSize(255); p.setResponseFragmentSize(0);
        p.setRequestTimeout(1); p.setDownstreamEncoding(""); p.setIpv6Transport(false);
        p.v.put(ProfileRepository.COLUMN_CONF_SHARED_KEY, ""); p.v.put(ProfileRepository.COLUMN_CONF_PROXY, 0);
        return p;
    }

	@Override
	public String toString() {
		return "[ConnectionProfile name=" + getName() + "]";
	}
}
